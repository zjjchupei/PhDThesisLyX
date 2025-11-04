*=======================================================================================
* PSM匹配结果诊断脚本
*=======================================================================================
* 用途：检查您得到的6000+观测是否合理
*=======================================================================================

cd "/Users/chupei/CTO_Prediction_Analysis-GEMINI/data/inter_data"

*------------------------------------------------------------------------------
* 第一步：检查最终结果的基本信息
*------------------------------------------------------------------------------
use "psm_sample9/PSM_5y_corrected.dta", clear

di "========================================="
di "第一步：总体数据规模"
di "========================================="

* 总观测数
qui count
di "总观测数：" r(N)

* 按时间窗口统计
tab t, missing

* 按treatment/control统计
qui count if treat == 1
local n_treat = r(N)
qui count if treat == 0
local n_control = r(N)
di ""
di "Treatment观测数：" `n_treat'
di "Control观测数：" `n_control'

*------------------------------------------------------------------------------
* 第二步：检查匹配对数量（最关键）
*------------------------------------------------------------------------------
di ""
di "========================================="
di "第二步：匹配对数量分析"
di "========================================="

* 在事件年（t=0）统计匹配对
preserve
keep if t == 0

* 总配对数
qui tab match_pair_id
local n_pairs = r(r)
di "总匹配对数：" `n_pairs'

* Treatment和Control数量
qui count if treat == 1
local n_treat_t0 = r(N)
qui count if treat == 0
local n_control_t0 = r(N)

di "  其中Treatment（事件年）：" `n_treat_t0'
di "  其中Control（事件年）：" `n_control_t0'

if `n_treat_t0' == `n_control_t0' & `n_treat_t0' == `n_pairs' {
    di "  ✓ 验证通过：1:1匹配结构正确"
}
else {
    di "  ⚠ 警告：匹配结构可能有问题"
}

* 理论数据量
local expected_obs = `n_pairs' * 2 * 8  // 匹配对数 × 2（treat+control） × 8年
di ""
di "理论观测数：" `expected_obs' " (匹配对数 × 2 × 8年)"

restore

* 实际与理论对比
qui count
local actual_obs = r(N)
local diff = `actual_obs' - `expected_obs'
di "实际观测数：" `actual_obs'
if `diff' != 0 {
    di "差异：" `diff' " （可能是部分年份数据缺失）"
}

*------------------------------------------------------------------------------
* 第三步：检查为什么匹配对数量少于预期
*------------------------------------------------------------------------------
di ""
di "========================================="
di "第三步：诊断匹配对数量"
di "========================================="

* 原始数据中有多少CTO事件
use "samplefull_final.dta", clear
qui count if cto_event == 1
local total_events = r(N)
di "原始数据CTO事件总数：" `total_events'

* 按年份统计
di ""
di "各年份CTO事件分布："
tab fyear if cto_event == 1

* 检查PSM匹配成功率
use "psm_sample9/PSM_5y_corrected.dta", clear
preserve
keep if t == 0 & treat == 1
qui count
local matched_events = r(N)
restore

di ""
di "成功匹配的事件数：" `matched_events'
di "未匹配的事件数：" `total_events' - `matched_events'
local match_rate = (`matched_events' / `total_events') * 100
di "匹配成功率：" %4.1f `match_rate' "%"

*------------------------------------------------------------------------------
* 第四步：分析未匹配的原因
*------------------------------------------------------------------------------
di ""
di "========================================="
di "第四步：未匹配原因分析"
di "========================================="

use "samplefull_final.dta", clear

* 统计各年份的potential controls
di "各年份可用控制组数量："
preserve
gen has_cto = 0
bys gvkey: replace has_cto = 1 if sum(cto_event) > 0
keep if has_cto == 0  // 只看从未有CTO事件的公司
collapse (count) n_controls=gvkey, by(fyear)
list fyear n_controls if fyear >= 2001 & fyear <= 2020
restore

* 检查协变量缺失情况
di ""
di "协变量缺失情况（可能导致匹配失败）："
foreach var in size xrd_at q roa {
    qui count if cto_event == 1 & missing(`var')
    if r(N) > 0 {
        di "  `var': " r(N) " 个treatment观测有缺失值"
    }
}

*------------------------------------------------------------------------------
* 第五步：检查控制组是否真的只用了一次
*------------------------------------------------------------------------------
di ""
di "========================================="
di "第五步：验证1:1匹配（重要）"
di "========================================="

use "psm_sample9/PSM_5y_corrected.dta", clear

* 检查每个控制组使用次数
preserve
keep if t == 0 & treat == 0
bys gvkey: gen n_times_used = _N
qui sum n_times_used

di "控制组使用次数统计："
di "  最小值：" r(min)
di "  最大值：" r(max)
di "  平均值：" r(mean)

if r(max) == 1 {
    di "  ✓ 完美：每个控制组只使用1次"
}
else {
    di "  ⚠ 警告：存在重复使用的控制组"
    tab n_times_used
}
restore

*------------------------------------------------------------------------------
* 第六步：按年份查看匹配情况
*------------------------------------------------------------------------------
di ""
di "========================================="
di "第六步：各年份匹配详情"
di "========================================="

preserve
keep if t == 0
tab match_year if treat == 1
restore

*------------------------------------------------------------------------------
* 总结
*------------------------------------------------------------------------------
di ""
di "========================================="
di "诊断总结"
di "========================================="
di ""
di "如果您的结果显示："
di ""
di "1. 匹配对数 < 498："
di "   原因可能是："
di "   - 协变量缺失值"
di "   - 卡尺太严格（0.05）"
di "   - 后续年份控制组耗尽"
di "   - 某些年份没有合适的控制组"
di ""
di "2. 总观测数约为 (匹配对数 × 2 × 8)："
di "   这是正常的，因为包含了前5年至后2年的数据"
di ""
di "3. 如果想要更多匹配对："
di "   - 放宽卡尺：caliper(0.05) → caliper(0.1)"
di "   - 检查并处理缺失值"
di "   - 考虑使用replacement matching（允许重复）"
di "   - 使用更少的协变量"
di ""

*=======================================================================================
* 可选：详细查看某一年的匹配情况
*=======================================================================================

di ""
di "示例：查看2015年的匹配详情"
di "-----------------------------------------"

use "psm_sample9/PSM_5y_corrected.dta", clear
keep if match_year == 2015 & t == 0

list gvkey treat size xrd_at q roa match_pair_id in 1/10, sep(0)

di ""
di "========================================="
di "诊断完成！"
di "========================================="
