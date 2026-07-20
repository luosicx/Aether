#!/usr/bin/env python3
# sonar-pr-comment.py
#
# 在 SonarCloud 分析完成后，自动将质量门状态、代码问题、覆盖率和评级
# 作为评论发布到 PR。若同一 PR 已有报告评论，则删除旧评论后创建新评论，
# 确保 PR 上始终只有一条最新报告。
#
# 环境变量：
#   SONAR_HOST_URL  SonarCloud 主机地址（默认 https://sonarcloud.io）
#   SONAR_TOKEN     SonarCloud API token
#   GH_TOKEN        GitHub token（用于评论 API）
#   PR_NUMBER       PR 编号
#   PROJECT_KEY     SonarCloud 项目 key（如 luosicx_Aether）
#   COMMIT_SHA      PR head commit SHA（用于评论中显示短 SHA）
#   REPO            GitHub 仓库（如 luosicx/Aether）

import base64
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request


def api_get(url, headers, timeout=30):
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read())


def rating_letter(val):
    try:
        return chr(64 + int(float(val)))  # 1->A, 2->B, ...
    except (ValueError, TypeError):
        return val or 'N/A'


def period(measures, key, default='0'):
    m = measures.get(key)
    if not m:
        return default
    ps = m.get('periods', [])
    return ps[0].get('value', default) if ps else default


def val(measures, m_key, default='N/A'):
    m = measures.get(m_key)
    return m.get('value', default) if m else default


def poll_quality_gate(sonar_host, headers, project_key, pr_number, attempts=15, interval=5):
    """轮询质量门状态，分析报告上传后需数秒处理。"""
    print(f"Polling SonarCloud quality gate for PR #{pr_number}...")
    for attempt in range(attempts):
        try:
            qg = api_get(
                f'{sonar_host}/api/qualitygates/project_status?projectKey={project_key}&pullRequest={pr_number}',
                headers,
            )
            if qg.get('projectStatus', {}).get('status'):
                print(f"  Quality gate ready (attempt {attempt+1}/{attempts})")
                return qg
        except urllib.error.HTTPError:
            if attempt == 0:
                print(f"  Waiting for analysis to be processed...")
        except Exception as e:
            print(f"  attempt {attempt+1}: {e}")
        time.sleep(interval)
    return None


def fetch_metrics(sonar_host, headers, project_key, pr_number):
    metrics = (
        'new_bugs,new_vulnerabilities,new_code_smells,new_coverage,'
        'new_duplicated_lines_density,new_lines,new_security_hotspots,'
        'new_security_hotspots_reviewed,bugs,vulnerabilities,code_smells,'
        'coverage,duplicated_lines_density,ncloc,sqale_rating,'
        'reliability_rating,security_rating'
    )
    try:
        mr = api_get(
            f'{sonar_host}/api/measures/component?component={project_key}&pullRequest={pr_number}&metricKeys={metrics}',
            headers,
        )
        return {m['metric']: m for m in mr.get('component', {}).get('measures', [])}
    except Exception as e:
        print(f"WARNING: measures fetch failed: {e}")
        return {}


def fetch_issues(sonar_host, headers, project_key, pr_number):
    try:
        ir = api_get(
            f'{sonar_host}/api/issues/search?componentKeys={project_key}&pullRequest={pr_number}&ps=100',
            headers,
        )
        return ir.get('issues', [])
    except Exception as e:
        print(f"WARNING: issues fetch failed: {e}")
        return []


def build_markdown(qg, measures, issues, sonar_host, project_key, pr_number, commit_sha):
    ps = qg.get('projectStatus', {})
    qg_status = ps.get('status', 'UNKNOWN')
    conditions = ps.get('conditions', [])

    new_bugs = period(measures, 'new_bugs')
    new_vulns = period(measures, 'new_vulnerabilities')
    new_smells = period(measures, 'new_code_smells')
    new_hotspots = period(measures, 'new_security_hotspots')
    new_coverage = period(measures, 'new_coverage', 'N/A')
    new_dup = period(measures, 'new_duplicated_lines_density', 'N/A')
    new_lines = period(measures, 'new_lines')
    hotspots_reviewed = period(measures, 'new_security_hotspots_reviewed', 'N/A')

    total_bugs = val(measures, 'bugs', '0')
    total_vulns = val(measures, 'vulnerabilities', '0')
    total_smells = val(measures, 'code_smells', '0')
    total_coverage = val(measures, 'coverage', 'N/A')
    total_dup = val(measures, 'duplicated_lines_density', 'N/A')
    ncloc = val(measures, 'ncloc', 'N/A')

    rel_rating = rating_letter(val(measures, 'reliability_rating'))
    sec_rating = rating_letter(val(measures, 'security_rating'))
    maint_rating = rating_letter(val(measures, 'sqale_rating'))

    metric_names = {
        'new_reliability_rating': '新代码可靠性评级',
        'new_security_rating': '新代码安全性评级',
        'new_maintainability_rating': '新代码可维护性评级',
        'new_coverage': '新代码覆盖率',
        'new_duplicated_lines_density': '新代码重复率',
        'new_security_hotspots_reviewed': '安全热点审查率',
    }
    cond_rows = []
    for c in conditions:
        mk = c.get('metricKey', '')
        name = metric_names.get(mk, mk)
        cstatus = c.get('status', '')
        icon = '✅' if cstatus == 'OK' else '❌'
        comp = c.get('comparator', '')
        threshold = c.get('errorThreshold', '')
        actual = c.get('actualValue', '')
        comp_text = {'LT': '≥', 'GT': '≤'}.get(comp, comp)
        cond_rows.append(f'| {name} | {comp_text} {threshold} | {actual} | {icon} {cstatus} |')

    qg_icon = '✅ PASSED' if qg_status == 'OK' else '❌ FAILED' if qg_status == 'ERROR' else qg_status
    dashboard_url = f"{sonar_host}/dashboard?id={project_key}&pullRequest={pr_number}"

    md = []
    md.append('<!-- sonarcloud-report -->')
    md.append('## 🔍 SonarCloud 代码质量分析报告')
    md.append('')
    md.append(f'**分析提交:** `{commit_sha}`  ')
    md.append(f'**SonarCloud 面板:** [查看完整报告]({dashboard_url})')
    md.append('')
    md.append('---')
    md.append('')
    md.append(f'### 质量门状态: {qg_icon}')
    md.append('')
    md.append('| 条件 | 阈值 | 实际值 | 结果 |')
    md.append('|------|------|--------|------|')
    md.extend(cond_rows)
    md.append('')
    md.append('### 代码问题统计')
    md.append('')
    md.append('| 类型 | 新代码 | 全量代码 |')
    md.append('|------|--------|----------|')
    md.append(f'| 🐛 Bug | {new_bugs} | {total_bugs} |')
    md.append(f'| 🔒 漏洞 | {new_vulns} | {total_vulns} |')
    md.append(f'| 💨 代码异味 | {new_smells} | {total_smells} |')
    md.append(f'| 🔥 安全热点 | {new_hotspots} | — |')
    md.append('')
    md.append('### 覆盖率与代码指标')
    md.append('')
    md.append('| 指标 | 值 |')
    md.append('|------|-----|')
    md.append(f'| 新代码行数 | {new_lines} 行 |')
    md.append(f'| 新代码覆盖率 | {new_coverage}% |')
    md.append(f'| 整体覆盖率 | {total_coverage}% |')
    md.append(f'| 新代码重复率 | {new_dup}% |')
    md.append(f'| 整体重复率 | {total_dup}% |')
    md.append(f'| 代码行数 (NCLOC) | {ncloc} |')
    md.append('')
    md.append('### 代码评级')
    md.append('')
    md.append('| 维度 | 评级 |')
    md.append('|------|------|')
    md.append(f'| 可靠性 | {rel_rating} |')
    md.append(f'| 安全性 | {sec_rating} |')
    md.append(f'| 可维护性 | {maint_rating} |')
    md.append('')

    if issues:
        md.append('### 问题详情')
        md.append('')
        md.append('| 严重度 | 类型 | 文件 | 描述 |')
        md.append('|--------|------|------|------|')
        for i in issues[:20]:
            sev = i.get('severity', '')
            typ = i.get('type', '')
            comp = i.get('component', '').replace(f'{project_key}:', '')
            line = i.get('line', '')
            msg = i.get('message', '')[:80]
            loc = f'{comp}:{line}' if line else comp
            md.append(f'| {sev} | {typ} | {loc} | {msg} |')
        if len(issues) > 20:
            md.append(f'| ... | ... | ... | 还有 {len(issues)-20} 个问题 |')
        md.append('')

    md.append('---')
    md.append('> _由 CI `code-quality` job 自动生成，数据来源: SonarCloud API_')

    return '\n'.join(md)


def delete_old_comments(repo, pr_number):
    """通过 HTML 标记 sonarcloud-report 查找并删除所有旧报告评论。"""
    result = subprocess.run(
        ['gh', 'api', f'repos/{repo}/issues/{pr_number}/comments', '--paginate',
         '--jq', '.[] | select(.body | contains("<!-- sonarcloud-report -->")) | .id'],
        capture_output=True, text=True,
    )
    existing_ids = [x.strip() for x in result.stdout.strip().split('\n') if x.strip()]
    if existing_ids:
        for cid in existing_ids:
            print(f"Deleting old comment {cid}")
            subprocess.run(
                ['gh', 'api', '--method', 'DELETE', f'repos/{repo}/issues/comments/{cid}'],
                capture_output=True,
            )


def create_new_comment(repo, pr_number, comment_body):
    """创建新评论（始终为最新内容，出现在 PR 评论列表顶部）。"""
    comment_file = '/tmp/sonar_comment.md'
    with open(comment_file, 'w') as f:
        f.write(comment_body)
    print("Creating new PR comment")
    subprocess.run(
        ['gh', 'api', '--method', 'POST',
         f'repos/{repo}/issues/{pr_number}/comments',
         '-F', f'body=@{comment_file}'],
        check=True,
    )
    print("Created new comment")


def main():
    sonar_host = (os.environ.get('SONAR_HOST_URL') or 'https://sonarcloud.io').rstrip('/')
    sonar_token = os.environ.get('SONAR_TOKEN')
    project_key = os.environ.get('PROJECT_KEY')
    pr_number = os.environ.get('PR_NUMBER')
    commit_sha = (os.environ.get('COMMIT_SHA') or '')[:7]
    repo = os.environ.get('REPO', 'luosicx/Aether')

    if not all([sonar_token, project_key, pr_number]):
        print("ERROR: SONAR_TOKEN, PROJECT_KEY, PR_NUMBER environment variables required", file=sys.stderr)
        sys.exit(1)

    auth = base64.b64encode(f'{sonar_token}:'.encode()).decode()
    headers = {'Authorization': f'Basic {auth}'}

    # 1. 轮询质量门状态
    qg = poll_quality_gate(sonar_host, headers, project_key, pr_number)
    if not qg:
        print("WARNING: SonarCloud quality gate unavailable, skipping PR comment")
        sys.exit(0)

    # 2. 获取度量指标
    measures = fetch_metrics(sonar_host, headers, project_key, pr_number)

    # 3. 获取问题列表
    issues = fetch_issues(sonar_host, headers, project_key, pr_number)

    # 4. 生成 Markdown
    comment_body = build_markdown(qg, measures, issues, sonar_host, project_key, pr_number, commit_sha)

    # 5. 删除旧评论并创建新评论
    delete_old_comments(repo, pr_number)
    create_new_comment(repo, pr_number, comment_body)


if __name__ == "__main__":
    main()
