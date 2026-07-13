#!/usr/bin/env python3
"""Add translations for ja, ko, fr, de, es to Localizable.xcstrings.

For the most visible strings (settings labels, button titles, section headers),
provides actual translations. For other strings, adds language entries with
"new" state so Xcode recognizes the languages.
"""
import json
from pathlib import Path

xcstrings_path = Path('Aether/Resources/Localizable.xcstrings')
data = json.loads(xcstrings_path.read_text(encoding='utf-8'))
strings = data.get('strings', {})

NEW_LANGS = ['ja', 'ko', 'fr', 'de', 'es']

# Translations for the most visible UI strings
# Format: { "zh-Hans key": {"ja": "...", "ko": "...", "fr": "...", "de": "...", "es": "..."} }
TRANSLATIONS = {
    "设置": {"ja": "設定", "ko": "설정", "fr": "Paramètres", "de": "Einstellungen", "es": "Ajustes"},
    "完成": {"ja": "完了", "ko": "완료", "fr": "Terminé", "de": "Fertig", "es": "Listo"},
    "取消": {"ja": "キャンセル", "ko": "취소", "fr": "Annuler", "de": "Abbrechen", "es": "Cancelar"},
    "删除": {"ja": "削除", "ko": "삭제", "fr": "Supprimer", "de": "Löschen", "es": "Eliminar"},
    "保存": {"ja": "保存", "ko": "저장", "fr": "Enregistrer", "de": "Speichern", "es": "Guardar"},
    "确认删除": {"ja": "削除の確認", "ko": "삭제 확인", "fr": "Confirmer la suppression", "de": "Löschen bestätigen", "es": "Confirmar eliminación"},
    "语言": {"ja": "言語", "ko": "언어", "fr": "Langue", "de": "Sprache", "es": "Idioma"},
    "跟随系统": {"ja": "システムに従う", "ko": "시스템 따르기", "fr": "Suivre le système", "de": "System folgen", "es": "Seguir el sistema"},
    "简体中文": {"ja": "簡体字中国語", "ko": "간체 중국어", "fr": "Chinois simplifié", "de": "Vereinfachtes Chinesisch", "es": "Chino simplificado"},
    "繁体中文": {"ja": "繁体字中国語", "ko": "번체 중국어", "fr": "Chinois traditionnel", "de": "Traditionelles Chinesisch", "es": "Chino tradicional"},
    "英文": {"ja": "英語", "ko": "영어", "fr": "Anglais", "de": "Englisch", "es": "Inglés"},
    "日本語": {"ja": "日本語", "ko": "일본어", "fr": "Japonais", "de": "Japanisch", "es": "Japonés"},
    "한국어": {"ja": "韓国語", "ko": "한국어", "fr": "Coréen", "de": "Koreanisch", "es": "Coreano"},
    "Français": {"ja": "フランス語", "ko": "프랑스어", "fr": "Français", "de": "Französisch", "es": "Francés"},
    "Deutsch": {"ja": "ドイツ語", "ko": "독일어", "fr": "Allemand", "de": "Deutsch", "es": "Alemán"},
    "Español": {"ja": "スペイン語", "ko": "스페인어", "fr": "Espagnol", "de": "Spanisch", "es": "Español"},
    "供应商": {"ja": "プロバイダー", "ko": "제공자", "fr": "Fournisseur", "de": "Anbieter", "es": "Proveedor"},
    "自动降级": {"ja": "自動フォールバック", "ko": "자동 폴백", "fr": "Repli automatique", "de": "Automatischer Fallback", "es": "Respaldo automático"},
    "启用自动降级": {"ja": "自動フォールバックを有効化", "ko": "자동 폴백 활성화", "fr": "Activer le repli automatique", "de": "Automatischen Fallback aktivieren", "es": "Activar respaldo automático"},
    "BFF 代理": {"ja": "BFFプロキシ", "ko": "BFF 프록시", "fr": "Proxy BFF", "de": "BFF-Proxy", "es": "Proxy BFF"},
    "启用 BFF 代理": {"ja": "BFFプロキシを有効化", "ko": "BFF 프록시 활성화", "fr": "Activer le proxy BFF", "de": "BFF-Proxy aktivieren", "es": "Activar proxy BFF"},
    "端侧推理": {"ja": "オンデバイス推論", "ko": "온디바이스 추론", "fr": "Inférence sur appareil", "de": "On-Device-Inferenz", "es": "Inferencia en dispositivo"},
    "启用端侧推理": {"ja": "オンデバイス推論を有効化", "ko": "온디바이스 추론 활성화", "fr": "Activer l'inférence sur appareil", "de": "On-Device-Inferenz aktivieren", "es": "Activar inferencia en dispositivo"},
    "管理端侧模型": {"ja": "オンデバイスモデルを管理", "ko": "온디바이스 모델 관리", "fr": "Gérer les modèles sur appareil", "de": "On-Device-Modelle verwalten", "es": "Gestionar modelos en dispositivo"},
    "断网自动切换": {"ja": "通信切断時の自動切替", "ko": "네트워크 끊김 시 자동 전환", "fr": "Bascule automatique hors ligne", "de": "Automatische Umschaltung bei Netzwerkverlust", "es": "Cambio automático sin red"},
    "健康管理": {"ja": "ヘルス管理", "ko": "건강 관리", "fr": "Gestion santé", "de": "Gesundheitsverwaltung", "es": "Gestión de salud"},
    "健康": {"ja": "ヘルス", "ko": "건강", "fr": "Santé", "de": "Gesundheit", "es": "Salud"},
    "语音朗读": {"ja": "音声読み上げ", "ko": "음성 읽기", "fr": "Lecture vocale", "de": "Sprachausgabe", "es": "Lectura de voz"},
    "音色": {"ja": "音声", "ko": "음색", "fr": "Voix", "de": "Stimme", "es": "Voz"},
    "系统默认": {"ja": "システムデフォルト", "ko": "시스템 기본값", "fr": "Système par défaut", "de": "Systemstandard", "es": "Predeterminado del sistema"},
    "API 配置": {"ja": "API設定", "ko": "API 설정", "fr": "Configuration API", "de": "API-Konfiguration", "es": "Configuración API"},
    "模型": {"ja": "モデル", "ko": "모델", "fr": "Modèle", "de": "Modell", "es": "Modelo"},
    "功能开关": {"ja": "機能スイッチ", "ko": "기능 토글", "fr": "Commutateurs de fonction", "de": "Funktionsschalter", "es": "Interruptores de función"},
    "插件管理": {"ja": "プラグイン管理", "ko": "플러그인 관리", "fr": "Gestion des plugins", "de": "Plugin-Verwaltung", "es": "Gestión de plugins"},
    "MCP 配置": {"ja": "MCP設定", "ko": "MCP 설정", "fr": "Configuration MCP", "de": "MCP-Konfiguration", "es": "Configuración MCP"},
    "系统提示词": {"ja": "システムプロンプト", "ko": "시스템 프롬프트", "fr": "Invite système", "de": "System-Prompt", "es": "Prompt del sistema"},
    "用户偏好": {"ja": "ユーザー設定", "ko": "사용자 선호도", "fr": "Préférences utilisateur", "de": "Benutzereinstellungen", "es": "Preferencias de usuario"},
    "主题": {"ja": "テーマ", "ko": "테마", "fr": "Thème", "de": "Theme", "es": "Tema"},
    "AI 人设": {"ja": "AIペルソナ", "ko": "AI 페르소나", "fr": "Personnalité IA", "de": "KI-Persona", "es": "Personalidad de IA"},
    "AI 头像": {"ja": "AIアバター", "ko": "AI 아바타", "fr": "Avatar IA", "de": "KI-Avatar", "es": "Avatar de IA"},
    "气泡样式": {"ja": "バブルスタイル", "ko": "버블 스타일", "fr": "Style de bulle", "de": "Blasenstil", "es": "Estilo de burbuja"},
    "字体与行距": {"ja": "フォントと行間", "ko": "글꼴과 줄 간격", "fr": "Police et interligne", "de": "Schriftart und Zeilenabstand", "es": "Fuente e interlineado"},
    "调试面板": {"ja": "デバッグパネル", "ko": "디버그 패널", "fr": "Panneau de débogage", "de": "Debug-Panel", "es": "Panel de depuración"},
    "关于": {"ja": "について", "ko": "정보", "fr": "À propos", "de": "Über", "es": "Acerca de"},
    "隐私政策": {"ja": "プライバシーポリシー", "ko": "개인정보처리방침", "fr": "Politique de confidentialité", "de": "Datenschutzrichtlinie", "es": "Política de privacidad"},
    "投诉反馈": {"ja": "フィードバック", "ko": "피드백", "fr": "Commentaires", "de": "Feedback", "es": "Comentarios"},
    "版本": {"ja": "バージョン", "ko": "버전", "fr": "Version", "de": "Version", "es": "Versión"},
    "以太": {"ja": "以太", "ko": "이더", "fr": "Aether", "de": "Aether", "es": "Aether"},
    "以太隐私政策": {"ja": "以太プライバシーポリシー", "ko": "이더 개인정보처리방침", "fr": "Politique de confidentialité d'Aether", "de": "Aether Datenschutzrichtlinie", "es": "Política de privacidad de Aether"},
    "API 与模型": {"ja": "APIとモデル", "ko": "API 및 모델", "fr": "API et modèles", "de": "API und Modelle", "es": "API y modelos"},
    "推理配置": {"ja": "推論設定", "ko": "추론 설정", "fr": "Configuration d'inférence", "de": "Inferenzkonfiguration", "es": "Configuración de inferencia"},
    "功能与偏好": {"ja": "機能と設定", "ko": "기능 및 선호도", "fr": "Fonctions et préférences", "de": "Funktionen und Einstellungen", "es": "Funciones y preferencias"},
    "发送": {"ja": "送信", "ko": "전송", "fr": "Envoyer", "de": "Senden", "es": "Enviar"},
    "复制": {"ja": "コピー", "ko": "복사", "fr": "Copier", "de": "Kopieren", "es": "Copiar"},
    "已复制": {"ja": "コピーしました", "ko": "복사됨", "fr": "Copié", "de": "Kopiert", "es": "Copiado"},
    "重命名": {"ja": "名前変更", "ko": "이름 변경", "fr": "Renommer", "de": "Umbenennen", "es": "Renombrar"},
    "新建对话": {"ja": "新規会話", "ko": "새 대화", "fr": "Nouvelle conversation", "de": "Neue Konversation", "es": "Nueva conversación"},
    "编辑": {"ja": "編集", "ko": "편집", "fr": "Modifier", "de": "Bearbeiten", "es": "Editar"},
    "确定": {"ja": "OK", "ko": "확인", "fr": "OK", "de": "OK", "es": "OK"},
    "工具调用": {"ja": "ツール呼び出し", "ko": "도구 호출", "fr": "Appel d'outil", "de": "Werkzeugaufruf", "es": "Llamada de herramienta"},
    "朗读": {"ja": "読み上げ", "ko": "읽기", "fr": "Lire à voix haute", "de": "Vorlesen", "es": "Leer en voz alta"},
    "停止朗读": {"ja": "読み上げを停止", "ko": "읽기 중지", "fr": "Arrêter la lecture", "de": "Lesen stoppen", "es": "Detener lectura"},
    "重新生成": {"ja": "再生成", "ko": "재생성", "fr": "Régénérer", "de": "Neu generieren", "es": "Regenerar"},
    "从此处分叉": {"ja": "ここから分岐", "ko": "여기서 분기", "fr": "Créer une branche ici", "de": "Hier abzweigen", "es": "Bifurcar desde aquí"},
    "已下载": {"ja": "ダウンロード済み", "ko": "다운로드됨", "fr": "Téléchargé", "de": "Heruntergeladen", "es": "Descargado"},
    "未下载": {"ja": "未ダウンロード", "ko": "미다운로드", "fr": "Non téléchargé", "de": "Nicht heruntergeladen", "es": "No descargado"},
    "下载": {"ja": "ダウンロード", "ko": "다운로드", "fr": "Télécharger", "de": "Herunterladen", "es": "Descargar"},
    "确认删除": {"ja": "削除の確認", "ko": "삭제 확인", "fr": "Confirmer la suppression", "de": "Löschen bestätigen", "es": "Confirmar eliminación"},
    "下载源": {"ja": "ダウンロード元", "ko": "다운로드 소스", "fr": "Source de téléchargement", "de": "Download-Quelle", "es": "Fuente de descarga"},
    "可用模型": {"ja": "利用可能なモデル", "ko": "사용 가능한 모델", "fr": "Modèles disponibles", "de": "Verfügbare Modelle", "es": "Modelos disponibles"},
    "端侧模型管理": {"ja": "オンデバイスモデル管理", "ko": "온디바이스 모델 관리", "fr": "Gestion des modèles sur appareil", "de": "On-Device-Modellverwaltung", "es": "Gestión de modelos en dispositivo"},
    "安装示例插件": {"ja": "サンプルプラグインをインストール", "ko": "샘플 플러그인 설치", "fr": "Installer le plugin d'exemple", "de": "Beispiel-Plugin installieren", "es": "Instalar plugin de ejemplo"},
    "已安装插件": {"ja": "インストール済みプラグイン", "ko": "설치된 플러그인", "fr": "Plugins installés", "de": "Installierte Plugins", "es": "Plugins instalados"},
    "安装": {"ja": "インストール", "ko": "설치", "fr": "Installer", "de": "Installieren", "es": "Instalar"},
    "暂无已安装插件": {"ja": "インストールされたプラグインはありません", "ko": "설치된 플러그인이 없습니다", "fr": "Aucun plugin installé", "de": "Keine Plugins installiert", "es": "No hay plugins instalados"},
    "授权状态": {"ja": "認証状態", "ko": "인증 상태", "fr": "État d'autorisation", "de": "Autorisierungsstatus", "es": "Estado de autorización"},
    "请求授权": {"ja": "認証を要求", "ko": "인증 요청", "fr": "Demander l'autorisation", "de": "Autorisierung anfordern", "es": "Solicitar autorización"},
    "已授权": {"ja": "認証済み", "ko": "인증됨", "fr": "Autorisé", "de": "Autorisiert", "es": "Autorizado"},
    "未授权": {"ja": "未認証", "ko": "미인증", "fr": "Non autorisé", "de": "Nicht autorisiert", "es": "No autorizado"},
    "跳转系统设置": {"ja": "システム設定へ移動", "ko": "시스템 설정으로 이동", "fr": "Aller aux paramètres système", "de": "Zu Systemeinstellungen", "es": "Ir a ajustes del sistema"},
    "注入健康上下文": {"ja": "ヘルスコンテキストを注入", "ko": "건강 컨텍스트 주입", "fr": "Injecter le contexte santé", "de": "Gesundheitskontext einfügen", "es": "Inyectar contexto de salud"},
    "立即生成洞察": {"ja": "今すぐインサイトを生成", "ko": "즉시 인사이트 생성", "fr": "Générer des insights maintenant", "de": "Insights jetzt generieren", "es": "Generar insights ahora"},
    "洞察": {"ja": "インサイト", "ko": "인사이트", "fr": "Insights", "de": "Insights", "es": "Insights"},
    "试听示例": {"ja": "サンプルを試聴", "ko": "샘플 미리듣기", "fr": "Écouter l'exemple", "de": "Beispiel anhören", "es": "Escuchar ejemplo"},
    "停止试听": {"ja": "試聴を停止", "ko": "미리듣기 중지", "fr": "Arrêter l'aperçu", "de": "Vorschau stoppen", "es": "Detener vista previa"},
    "选择图片": {"ja": "画像を選択", "ko": "이미지 선택", "fr": "Sélectionner une image", "de": "Bild auswählen", "es": "Seleccionar imagen"},
    "开始录音": {"ja": "録音開始", "ko": "녹음 시작", "fr": "Commencer l'enregistrement", "de": "Aufnahme starten", "es": "Iniciar grabación"},
    "停止录音": {"ja": "録音停止", "ko": "녹음 중지", "fr": "Arrêter l'enregistrement", "de": "Aufnahme stoppen", "es": "Detener grabación"},
    "知识库": {"ja": "ナレッジベース", "ko": "지식 베이스", "fr": "Base de connaissances", "de": "Wissensdatenbank", "es": "Base de conocimiento"},
    "MCP Server 列表": {"ja": "MCPサーバーリスト", "ko": "MCP 서버 목록", "fr": "Liste des serveurs MCP", "de": "MCP-Server-Liste", "es": "Lista de servidores MCP"},
    "添加 Server": {"ja": "サーバーを追加", "ko": "서버 추가", "fr": "Ajouter un serveur", "de": "Server hinzufügen", "es": "Añadir servidor"},
    "已连接": {"ja": "接続済み", "ko": "연결됨", "fr": "Connecté", "de": "Verbunden", "es": "Conectado"},
    "未连接": {"ja": "未接続", "ko": "미연결", "fr": "Non connecté", "de": "Nicht verbunden", "es": "No conectado"},
    "连接中": {"ja": "接続中", "ko": "연결 중", "fr": "Connexion en cours", "de": "Verbinde", "es": "Conectando"},
    "错误": {"ja": "エラー", "ko": "오류", "fr": "Erreur", "de": "Fehler", "es": "Error"},
    "已启用": {"ja": "有効", "ko": "활성화됨", "fr": "Activé", "de": "Aktiviert", "es": "Activado"},
    "已禁用": {"ja": "無効", "ko": "비활성화됨", "fr": "Désactivé", "de": "Deaktiviert", "es": "Desactivado"},
    "基本信息": {"ja": "基本情報", "ko": "기본 정보", "fr": "Informations de base", "de": "Grundinformationen", "es": "Información básica"},
    "传输配置": {"ja": "転送設定", "ko": "전송 설정", "fr": "Configuration de transport", "de": "Transportkonfiguration", "es": "Configuración de transporte"},
    "名称": {"ja": "名前", "ko": "이름", "fr": "Nom", "de": "Name", "es": "Nombre"},
    "启用": {"ja": "有効", "ko": "활성화", "fr": "Activer", "de": "Aktivieren", "es": "Activar"},
    "命令路径": {"ja": "コマンドパス", "ko": "명령어 경로", "fr": "Chemin de commande", "de": "Befehlspfad", "es": "Ruta de comando"},
    "参数": {"ja": "パラメータ", "ko": "매개변수", "fr": "Paramètres", "de": "Parameter", "es": "Parámetros"},
    "预设角色": {"ja": "プリセット役割", "ko": "사전 설정 역할", "fr": "Rôle prédéfini", "de": "Vordefinierte Rolle", "es": "Rol predefinido"},
    "选择角色": {"ja": "役割を選択", "ko": "역할 선택", "fr": "Choisir un rôle", "de": "Rolle wählen", "es": "Elegir rol"},
    "默认": {"ja": "デフォルト", "ko": "기본값", "fr": "Par défaut", "de": "Standard", "es": "Predeterminado"},
    "正式": {"ja": "フォーマル", "ko": "격식", "fr": "Formel", "de": "Formell", "es": "Formal"},
    "轻松": {"ja": "カジュアル", "ko": "캐주얼", "fr": "Décontracté", "de": "Locker", "es": "Casual"},
    "清除头像": {"ja": "アバターを削除", "ko": "아바타 삭제", "fr": "Effacer l'avatar", "de": "Avatar löschen", "es": "Borrar avatar"},
    "从相册选择头像": {"ja": "写真からアバターを選択", "ko": "앨범에서 아바타 선택", "fr": "Choisir un avatar depuis l'album", "de": "Avatar aus Album wählen", "es": "Elegir avatar del álbum"},
    "预览": {"ja": "プレビュー", "ko": "미리보기", "fr": "Aperçu", "de": "Vorschau", "es": "Vista previa"},
    "查看调试信息": {"ja": "デバッグ情報を表示", "ko": "디버그 정보 보기", "fr": "Voir les infos de débogage", "de": "Debug-Info anzeigen", "es": "Ver info de depuración"},
    "性能指标": {"ja": "パフォーマンス指標", "ko": "성능 지표", "fr": "Indicateurs de performance", "de": "Leistungskennzahlen", "es": "Indicadores de rendimiento"},
    "远程配置 / 遥测": {"ja": "リモート設定 / テレメトリ", "ko": "원격 설정 / 원격 측정", "fr": "Config distante / Télémétrie", "de": "Remote-Konfig / Telemetrie", "es": "Config remota / Telemetría"},
    "供应商与降级": {"ja": "プロバイダーとフォールバック", "ko": "제공자 및 폴백", "fr": "Fournisseur et repli", "de": "Anbieter und Fallback", "es": "Proveedor y respaldo"},
    "当前供应商": {"ja": "現在のプロバイダー", "ko": "현재 제공자", "fr": "Fournisseur actuel", "de": "Aktueller Anbieter", "es": "Proveedor actual"},
    "选中模型": {"ja": "選択中のモデル", "ko": "선택된 모델", "fr": "Modèle sélectionné", "de": "Ausgewähltes Modell", "es": "Modelo seleccionado"},
    "触发降级": {"ja": "フォールバック発生", "ko": "폴백 트리거", "fr": "Repli déclenché", "de": "Fallback ausgelöst", "es": "Respaldo activado"},
    "是": {"ja": "はい", "ko": "예", "fr": "Oui", "de": "Ja", "es": "Sí"},
    "否": {"ja": "いいえ", "ko": "아니오", "fr": "Non", "de": "Nein", "es": "No"},
    "无": {"ja": "なし", "ko": "없음", "fr": "Aucun", "de": "Keine", "es": "Ninguno"},
    "暂无数据": {"ja": "データなし", "ko": "데이터 없음", "fr": "Pas de données", "de": "Keine Daten", "es": "Sin datos"},
    "暂无最近对话": {"ja": "最近の会話はありません", "ko": "최근 대화 없음", "fr": "Pas de conversation récente", "de": "Keine letzten Konversationen", "es": "Sin conversaciones recientes"},
    "还没有对话": {"ja": "会話がありません", "ko": "대화가 없습니다", "fr": "Aucune conversation", "de": "Keine Konversationen", "es": "Sin conversaciones"},
    "搜索会话标题…": {"ja": "会話タイトルを検索…", "ko": "대화 제목 검색…", "fr": "Rechercher des conversations…", "de": "Konversationen suchen…", "es": "Buscar conversaciones…"},
    "置顶": {"ja": "ピン留め", "ko": "고정", "fr": "Épingler", "de": "Anheften", "es": "Fijar"},
    "取消置顶": {"ja": "ピン留めを解除", "ko": "고정 해제", "fr": "Désépingler", "de": "Lösen", "es": "Desfijar"},
    "全选": {"ja": "すべて選択", "ko": "전체 선택", "fr": "Tout sélectionner", "de": "Alle auswählen", "es": "Seleccionar todo"},
    "取消全选": {"ja": "すべて選択解除", "ko": "전체 선택 해제", "fr": "Tout désélectionner", "de": "Alle abwählen", "es": "Deseleccionar todo"},
    "批量删除": {"ja": "一括削除", "ko": "일괄 삭제", "fr": "Suppression en lot", "de": "Stapelweise löschen", "es": "Eliminación por lotes"},
    "删除对话": {"ja": "会話を削除", "ko": "대화 삭제", "fr": "Supprimer la conversation", "de": "Konversation löschen", "es": "Eliminar conversación"},
    "重命名对话": {"ja": "会話の名前変更", "ko": "대화 이름 변경", "fr": "Renommer la conversation", "de": "Konversation umbenennen", "es": "Renombrar conversación"},
    "新标题": {"ja": "新しいタイトル", "ko": "새 제목", "fr": "Nouveau titre", "de": "Neuer Titel", "es": "Nuevo título"},
    "输入消息…": {"ja": "メッセージを入力…", "ko": "메시지 입력…", "fr": "Saisir un message…", "de": "Nachricht eingeben…", "es": "Escribir mensaje…"},
    "无形，无处不在，智能": {"ja": "目に見えず、どこにでも、知的", "ko": "보이지 않으나 어디에나, 지능적으로", "fr": "Invisible, omniprésent, intelligent", "de": "Unsichtbar, allgegenwärtig, intelligent", "es": "Invisible, omnipresente, inteligente"},
    "更新日期：2026年7月": {"ja": "更新日：2026年7月", "ko": "업데이트 날짜: 2026년 7월", "fr": "Date de mise à jour : juillet 2026", "de": "Aktualisiert: Juli 2026", "es": "Fecha de actualización: julio 2026"},
}

added = 0
for key, entry in strings.items():
    localizations = entry.setdefault('localizations', {})
    if key in TRANSLATIONS:
        for lang in NEW_LANGS:
            if lang not in localizations:
                localizations[lang] = {
                    'stringUnit': {
                        'state': 'translated',
                        'value': TRANSLATIONS[key][lang]
                    }
                }
                added += 1
    else:
        for lang in NEW_LANGS:
            if lang not in localizations:
                localizations[lang] = {
                    'stringUnit': {
                        'state': 'new',
                        'value': ''
                    }
                }

# Sort localizations keys for consistency
for key, entry in strings.items():
    if 'localizations' in entry:
        sorted_locs = dict(sorted(entry['localizations'].items()))
        entry['localizations'] = sorted_locs

# Sort strings keys
data['strings'] = dict(sorted(strings.items()))

xcstrings_path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')
print(f'Added {added} translations for new languages')
print(f'Total strings: {len(strings)}')
