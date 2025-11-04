*=======================================================================================
*          Sample9: Year-by-Year 1:1 PSM (修正版 - 防止重复匹配)
*=======================================================================================
* 作者说明：此版本修正了原代码中控制组被重复匹配的问题
* 主要改进：
*   1. 确保每个控制组公司只被匹配一次
*   2. 正确追踪1:1匹配对关系
*   3. 避免面板数据构建时的重复
*=======================================================================================

clear all
set more off
set matsize 10000

cd "/Users/chupei/CTO_Prediction_Analysis-GEMINI/data/inter_data"

*------------------------------------------------------------------------------
* 第一步：准备主数据集
*------------------------------------------------------------------------------
use "samplefull_final.dta", clear

* 创建treatment标识和事件年份
bys gvkey: egen has_cto_event = max(cto_event)
bys gvkey (fyear): gen temp_event_year = fyear if cto_event == 1
bys gvkey: egen event_year = min(temp_event_year)
drop temp_event_year

* 标记每个观测的角色
gen is_treatment_event = (cto_event == 1)  // 事件发生当年的treatment
gen can_be_control = (has_cto_event == 0)  // 可以作为控制组的公司

* 保存主数据集
tempfile master_data
save `master_data', replace

di "========================================="
di "数据准备完成"
qui count if is_treatment_event == 1
di "Treatment事件数: " r(N)
qui count if can_be_control == 1
di "潜在控制组观测数: " r(N)
di "========================================="

*------------------------------------------------------------------------------
* 第二步：逐年PSM匹配，确保1:1且无重复
*------------------------------------------------------------------------------

* 创建存储所有匹配结果的临时文件
tempfile all_matched_pairs
clear
gen gvkey = ""
gen fyear = .
gen match_pair_id = .
gen is_treatment = .
gen match_year = .
save `all_matched_pairs', replace emptyok

* 存储已被匹配的控制组gvkey
tempfile used_controls
clear
gen gvkey = ""
gen used_in_year = .
save `used_controls', replace emptyok

* 逐年进行PSM匹配
forvalues year = 2001(1)2020 {

    di ""
    di "========================================="
    di "处理年份: `year'"
    di "========================================="

    * 加载当年数据
    use `master_data', clear
    keep if fyear == `year'

    * 排除已被使用的控制组
    merge m:1 gvkey using `used_controls', keep(1 3) nogen
    gen already_used = (used_in_year != .)

    * 当年可用的控制组
    gen available_control = (can_be_control == 1 & already_used == 0)

    * 统计
    qui count if is_treatment_event == 1
    local n_treat = r(N)
    qui count if available_control == 1
    local n_control = r(N)

    di "  Treatment数量: `n_treat'"
    di "  可用Control数量: `n_control'"

    if `n_treat' == 0 {
        di "  --> 跳过（无treatment）"
        continue
    }

    if `n_control' == 0 {
        di "  --> 跳过（无可用control）"
        continue
    }

    * 创建PSM用的treatment变量（只包含treatment和可用的control）
    gen psm_treat = .
    replace psm_treat = 1 if is_treatment_event == 1
    replace psm_treat = 0 if available_control == 1
    keep if psm_treat != .

    * 检查协变量缺失值
    foreach var in size xrd_at q roa {
        qui count if missing(`var')
        if r(N) > 0 {
            di "  警告: `var'有缺失值，删除这些观测"
            drop if missing(`var')
        }
    }

    qui count if psm_treat == 1
    local n_treat_final = r(N)
    qui count if psm_treat == 0
    local n_control_final = r(N)

    if `n_treat_final' == 0 | `n_control_final' == 0 {
        di "  --> 跳过（删除缺失值后样本不足）"
        continue
    }

    * 执行PSM (1:1匹配，卡尺0.05)
    di "  执行PSM匹配..."
    capture noisily psmatch2 psm_treat size xrd_at q roa, ///
        n(1) caliper(0.05) logit ties ate common

    if _rc != 0 {
        di "  --> PSM匹配失败，跳过"
        continue
    }

    * 检查匹配结果
    qui count if psm_treat == 1 & _weight != .
    local n_matched = r(N)
    di "  成功匹配: `n_matched' 对"

    if `n_matched' == 0 {
        di "  --> 无成功匹配，跳过"
        continue
    }

    *--------------------------------------------------------------------------
    * 提取匹配对（关键改进）
    *--------------------------------------------------------------------------

    * 为每个成功匹配的treatment分配配对ID
    gen pair_id = .
    gen matched_control_gvkey = ""

    * 记录treatment的信息
    gen row_num = _n
    qui sum row_num if psm_treat == 1 & _weight != ., meanonly
    local max_treat_row = r(max)

    local pair_counter = 0
    forvalues i = 1/`=_N' {

        * 检查这一行是否是matched treatment
        qui sum psm_treat if row_num == `i', meanonly
        if r(N) == 0 continue
        local is_treat = r(mean)

        qui sum _weight if row_num == `i', meanonly
        if r(N) == 0 continue
        local has_match = (r(mean) != .)

        if `is_treat' == 1 & `has_match' == 1 {

            local pair_counter = `pair_counter' + 1

            * 获取treatment的gvkey
            qui sum gvkey if row_num == `i', meanonly
            local treat_gvkey = r(mean)

            * 标记treatment
            qui replace pair_id = 1000*`year' + `pair_counter' if row_num == `i'

            * 获取匹配的control的行号
            qui sum _n1 if row_num == `i', meanonly
            if r(N) > 0 {
                local control_row = r(mean)

                * 获取control的gvkey
                preserve
                keep if row_num == `control_row'
                local control_gvkey = gvkey[1]
                restore

                * 标记control
                qui replace pair_id = 1000*`year' + `pair_counter' if row_num == `control_row'
                qui replace matched_control_gvkey = "`control_gvkey'" if row_num == `i'
            }
        }
    }

    * 保存匹配结果
    preserve
    keep if pair_id != .
    keep gvkey fyear pair_id psm_treat
    rename pair_id match_pair_id
    rename psm_treat is_treatment
    gen match_year = `year'

    * 添加到总匹配结果
    append using `all_matched_pairs'
    save `all_matched_pairs', replace
    restore

    * 更新已使用的控制组列表
    preserve
    keep if pair_id != . & psm_treat == 0
    keep gvkey
    gen used_in_year = `year'
    append using `used_controls'
    save `used_controls', replace
    restore

    di "  ✓ 完成 `pair_counter' 对匹配"
}

*------------------------------------------------------------------------------
* 第三步：构建包含时间窗口的面板数据
*------------------------------------------------------------------------------

di ""
di "========================================="
di "构建面板数据（事件前5年至事件后2年）"
di "========================================="

* 加载匹配结果
use `all_matched_pairs', clear

* 统计总体匹配情况
qui count
di "总匹配观测数: " r(N)
qui count if is_treatment == 1
di "  其中Treatment: " r(N)
qui count if is_treatment == 0
di "  其中Control: " r(N)

bys match_pair_id: gen pair_size = _N
tab pair_size  // 应该都是2（1个treatment + 1个control）

qui count if pair_size != 2
if r(N) > 0 {
    di "警告: 发现配对不完整，删除这些观测"
    drop if pair_size != 2
}

* 展开到包含前后窗口的面板数据
expand 8  // 5年前 + 事件年 + 2年后 = 8年
bys gvkey match_pair_id: gen time_index = _n - 6  // -5, -4, ..., 0, 1, 2
gen fyear_expanded = match_year + time_index
drop fyear time_index
rename fyear_expanded fyear

* 合并完整的变量信息
merge m:1 gvkey fyear using `master_data', ///
    keep(3) nogen ///
    keepusing(cto_event size xrd_at q roa cash leverage MtB dividends ///
             liquiR Pastprof quick_ratio rd_sale Inv Capx deltaTA CapxXrd Itotal Inew)

* 生成DID变量
bys gvkey: egen treat = max(is_treatment)
gen Post = (fyear >= match_year)
gen D = treat * Post
gen t = fyear - match_year

* 清理和排序
order gvkey fyear match_pair_id match_year t treat Post D is_treatment
sort match_pair_id is_treatment fyear
duplicates drop gvkey fyear, force

* 保存结果
save "psm_sample9/PSM_5y_corrected.dta", replace

di ""
di "========================================="
di "匹配完成！"
di "========================================="
qui count
di "最终观测数: " r(N)
qui tab match_pair_id
di "匹配对数: " r(r)

*------------------------------------------------------------------------------
* 第四步：匹配质量检验
*------------------------------------------------------------------------------

di ""
di "========================================="
di "匹配质量检验"
di "========================================="

* 检验1: 每个控制组只被使用一次
preserve
keep if t == 0 & treat == 0
bys gvkey: gen n_used = _N
qui sum n_used
di "检验1: 控制组使用次数统计"
di "  最小值: " r(min) "  最大值: " r(max) "  平均: " r(mean)
if r(max) > 1 {
    di "  ⚠ 警告: 存在被多次使用的控制组！"
    list gvkey match_year if n_used > 1
}
else {
    di "  ✓ 通过：所有控制组仅使用一次"
}
restore

* 检验2: 每个匹配对的结构
preserve
keep if t == 0
collapse (sum) n_treat=is_treatment (count) pair_size=gvkey, by(match_pair_id match_year)
gen n_control = pair_size - n_treat
di ""
di "检验2: 匹配对结构"
qui count if n_treat != 1 | n_control != 1
if r(N) > 0 {
    di "  ⚠ 警告: 存在配对不正确的匹配对"
    list if n_treat != 1 | n_control != 1
}
else {
    di "  ✓ 通过：所有匹配对均为1:1结构"
}
restore

* 检验3: 各年份匹配数量
di ""
di "检验3: 各年份匹配情况"
preserve
keep if t == 0 & treat == 1
tab match_year
restore

* 检验4: 平衡性检验（事件年的协变量）
preserve
keep if t == 0
di ""
di "检验4: 协变量平衡性检验（事件发生年）"
foreach var in size xrd_at q roa {
    qui ttest `var', by(treat)
    di "  `var': t=" %6.3f r(t) "  p=" %6.4f r(p)
}
restore

di ""
di "========================================="
di "数据已保存至: psm_sample9/PSM_5y_corrected.dta"
di "========================================="
di ""
di "建议的后续步骤："
di "1. 检查平衡性检验结果"
di "2. 绘制共同支撑图"
di "3. 运行平行趋势检验"
di "4. 进行DID回归分析"
di ""

*=======================================================================================
* 可选：绘制PSM质量图表
*=======================================================================================

* 如果需要绘制kernel density图和pstest，可以针对合并后的数据重新运行
* 注意：这需要重新计算所有观测的propensity score

use "psm_sample9/PSM_5y_corrected.dta", clear
keep if t == 0  // 只保留事件年

* 重新估计logit以获取propensity score
quietly logit treat size xrd_at q roa
predict ps_final

* 绘制密度图
twoway (kdensity ps_final if treat==1, lp(solid) lw(*2.5)) ///
       (kdensity ps_final if treat==0, lp(dash) lw(*2.5)), ///
       ytitle("Kernel Density", angle(0)) ylabel(, angle(0)) ///
       xtitle("Propensity Score") ///
       legend(label(1 "Treatment") label(2 "Control") ///
              row(2) position(2) ring(0)) ///
       title("After Year-by-Year 1:1 PSM") ///
       scheme(s2mono)

graph export "psm_sample9/psm_corrected_density.png", as(png) replace

di "Kernel density图已保存"
