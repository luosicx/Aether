package com.aether.ui.health

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.aether.data.api.AetherApi
import com.aether.data.model.HealthSummary
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 健康洞察 ViewModel。
 *
 * 通过 [AetherApi.getHealthSummary] 拉取指定日期的健康数据，
 * 通过 [AetherApi.uploadHealthSummary] 上传当前数据。
 */
class HealthViewModel(private val api: AetherApi) : ViewModel() {

    // 注意：dateFmt 必须在 _selectedDate 之前初始化，
    // 因为 _selectedDate 的初始化会调用 todayStr()，而 todayStr() 依赖 dateFmt。
    private val dateFmt = SimpleDateFormat("yyyy-MM-dd", Locale.US)

    private val _selectedDate = MutableStateFlow(todayStr())
    val selectedDate: StateFlow<String> = _selectedDate.asStateFlow()

    private val _healthSummary = MutableStateFlow<HealthSummary?>(null)
    val healthSummary: StateFlow<HealthSummary?> = _healthSummary.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _errorMessage = MutableStateFlow<String?>(null)
    val errorMessage: StateFlow<String?> = _errorMessage.asStateFlow()

    /**
     * 设置当前选中日期（格式 yyyy-MM-dd），并触发数据加载。
     */
    fun selectDate(date: String) {
        _selectedDate.value = date
        loadHealthSummary(date)
    }

    /**
     * 加载指定日期的健康摘要。
     *
     * @param date yyyy-MM-dd 字符串
     */
    fun loadHealthSummary(date: String) {
        _selectedDate.value = date
        _isLoading.value = true
        _errorMessage.value = null
        viewModelScope.launch {
            try {
                _healthSummary.value = api.getHealthSummary(date)
            } catch (e: Exception) {
                _errorMessage.value = "加载健康数据失败：${e.message}"
                _healthSummary.value = null
            } finally {
                _isLoading.value = false
            }
        }
    }

    /**
     * 上传当前 HealthSummary（若为 null 则上传当日空摘要）。
     */
    fun uploadCurrentSummary() {
        val summary = _healthSummary.value ?: HealthSummary(
            date = _selectedDate.value,
            steps = 0,
            sleepHours = 0.0,
            restingHeartRate = 0
        )
        _isLoading.value = true
        _errorMessage.value = null
        viewModelScope.launch {
            try {
                api.uploadHealthSummary(summary)
                // 上传成功后刷新该日数据
                _healthSummary.value = summary
            } catch (e: Exception) {
                _errorMessage.value = "上传健康数据失败：${e.message}"
            } finally {
                _isLoading.value = false
            }
        }
    }

    /**
     * 用作上传目标的当前摘要 setter（供 UI 编辑后上传）。
     */
    fun updateCurrentSummary(
        steps: Int? = null,
        sleepHours: Double? = null,
        restingHeartRate: Int? = null
    ) {
        val current = _healthSummary.value ?: HealthSummary(date = _selectedDate.value)
        _healthSummary.value = current.copy(
            steps = steps ?: current.steps,
            sleepHours = sleepHours ?: current.sleepHours,
            restingHeartRate = restingHeartRate ?: current.restingHeartRate
        )
    }

    /**
     * 清空错误状态。
     */
    fun clearError() {
        _errorMessage.value = null
    }

    private fun todayStr(): String = dateFmt.format(Date())
}
