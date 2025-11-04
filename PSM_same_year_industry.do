*=======================================================================================
*          同年度、同行业 1:1 PSM匹配（只保留事件年度数据）
*=======================================================================================
* 用途：在CTO任命年度，匹配同年度、同行业的控制组公司
* 特点：
*   1. 只保留事件发生年度的数据（不包含前后窗口）
*   2. 同年度匹配（同一个fyear）
*   3. 同行业匹配（同一个行业代码）
*   4. 1:1匹配且控制组不重复使用
*=======================================================================================

clear all
set more off
set matsize 10000

cd "/Users/chupei/CTO_Prediction_Analysis-GEMINI/data/inter_data"

*------------------------------------------------------------------------------
* 第一步：准备数据
*------------------------------------------------------------------------------
use "samplefull_final.dta", clear

di "========================================="
di "数据准备"
di "========================================="

* 检查是否有行业变量（常见名称：sic, industry, ind, naics等）
* 请根据您的数据调整行业变量名
capture confirm variable sic
if _rc == 0 {
    local ind_var "sic"
    di "使用行业变量: sic"
}
else {
    capture confirm variable industry
    if _rc == 0 {
        local ind_var "industry"
        di "使用行业变量: industry"
    }
    else {
        capture confirm variable ind
        if _rc == 0 {
            local ind_var "ind"
            di "使用行业变量: ind"
        }
        else {
            di "⚠ 警告：未找到行业变量（sic/industry/ind）"
            di "请在下面手动指定您的行业变量名"
            di "例如：local ind_var 'your_industry_variable'"
            exit
        }
    }
}

* 创建treatment标识
bys gvkey: egen has_cto_event = max(cto_event)
gen is_treatment_event = (cto_event == 1)
gen can_be_control = (has_cto_event == 0)

* 保存主数据
tempfile master_data
save `master_data', replace

qui count if is_treatment_event == 1
di "CTO事件总数: " r(N)
qui count if can_be_control == 1
di "潜在控制组观测数: " r(N)
di ""

*------------------------------------------------------------------------------
* 第二步：同年度、同行业PSM匹配
*------------------------------------------------------------------------------

di "========================================="
di "开始同年度、同行业1:1 PSM匹配"
di "========================================="
di ""

* 存储所有匹配结果
tempfile all_matched_pairs
clear
gen gvkey = ""
gen fyear = .
gen match_pair_id = .
gen is_treatment = .
gen match_year = .
save `all_matched_pairs', replace emptyok

* 存储已使用的控制组
tempfile used_controls
clear
gen gvkey = ""
gen used_in_year = .
save `used_controls', replace emptyok

* 逐年、逐行业进行PSM匹配
forvalues year = 2001(1)2020 {

    di "----------------------------------------"
    di "处理年份: `year'"
    di "----------------------------------------"

    use `master_data', clear
    keep if fyear == `year'

    * 排除已被使用的控制组
    merge m:1 gvkey using `used_controls', keep(1 3) nogen
    gen already_used = (used_in_year != .)
    gen available_control = (can_be_control == 1 & already_used == 0)

    * 统计当年的情况
    qui count if is_treatment_event == 1
    local n_treat_year = r(N)

    if `n_treat_year' == 0 {
        di "  跳过（无treatment）"
        continue
    }

    * 获取当年有treatment的行业列表
    preserve
    keep if is_treatment_event == 1
    levelsof `ind_var', local(industries)
    restore

    * 逐行业进行PSM
    foreach ind in `industries' {

        preserve
        keep if `ind_var' == `ind'

        qui count if is_treatment_event == 1
        local n_treat = r(N)
        qui count if available_control == 1
        local n_control = r(N)

        if `n_treat' == 0 | `n_control' == 0 {
            restore
            continue
        }

        di "  行业 `ind': Treatment=`n_treat', 可用Control=`n_control'"

        * 创建PSM用的treatment变量
        gen psm_treat = .
        replace psm_treat = 1 if is_treatment_event == 1
        replace psm_treat = 0 if available_control == 1
        keep if psm_treat != .

        * 检查协变量缺失
        foreach var in size xrd_at q roa {
            qui count if missing(`var')
            if r(N) > 0 {
                drop if missing(`var')
            }
        }

        qui count if psm_treat == 1
        local n_treat_final = r(N)
        qui count if psm_treat == 0
        local n_control_final = r(N)

        if `n_treat_final' == 0 | `n_control_final' == 0 {
            restore
            continue
        }

        * 执行PSM
        capture noisily psmatch2 psm_treat size xrd_at q roa, ///
            n(1) caliper(0.05) logit ties ate common quietly

        if _rc != 0 {
            restore
            continue
        }

        * 检查匹配结果
        qui count if psm_treat == 1 & _weight != .
        local n_matched = r(N)

        if `n_matched' == 0 {
            restore
            continue
        }

        di "    成功匹配 `n_matched' 对"

        * 提取匹配对
        gen pair_id = .
        gen row_num = _n
        local pair_counter = 0

        forvalues i = 1/`=_N' {
            qui sum psm_treat if row_num == `i', meanonly
            if r(N) == 0 continue
            local is_treat = r(mean)

            qui sum _weight if row_num == `i', meanonly
            if r(N) == 0 continue
            local has_match = (r(mean) != .)

            if `is_treat' == 1 & `has_match' == 1 {
                local pair_counter = `pair_counter' + 1

                * 标记treatment
                qui replace pair_id = 1000*`year' + 100*`ind' + `pair_counter' if row_num == `i'

                * 获取匹配的control
                qui sum _n1 if row_num == `i', meanonly
                if r(N) > 0 {
                    local control_row = r(mean)
                    qui replace pair_id = 1000*`year' + 100*`ind' + `pair_counter' if row_num == `control_row'
                }
            }
        }

        * 保存本行业的匹配结果
        keep if pair_id != .
        keep gvkey fyear pair_id psm_treat `ind_var'
        rename pair_id match_pair_id
        rename psm_treat is_treatment
        gen match_year = `year'
        gen match_industry = `ind'

        append using `all_matched_pairs'
        save `all_matched_pairs', replace

        * 更新已使用的控制组
        preserve
        keep if is_treatment == 0
        keep gvkey
        gen used_in_year = `year'
        append using `used_controls'
        save `used_controls', replace
        restore

        restore
    }
}

*------------------------------------------------------------------------------
* 第三步：合并完整变量并保存
*------------------------------------------------------------------------------

di ""
di "========================================="
di "合并完整变量信息"
di "========================================="

use `all_matched_pairs', clear

* 统计
qui count
di "总匹配观测数: " r(N)
qui count if is_treatment == 1
di "  Treatment: " r(N)
qui count if is_treatment == 0
di "  Control: " r(N)
qui tab match_pair_id
di "总匹配对数: " r(r)

* 检查配对完整性
bys match_pair_id: gen pair_size = _N
tab pair_size

qui count if pair_size != 2
if r(N) > 0 {
    di "警告: 删除不完整的配对"
    drop if pair_size != 2
}

* 合并完整的数据
merge m:1 gvkey fyear using `master_data', keep(3) nogen

* 生成treatment变量
bys gvkey: egen treat = max(is_treatment)

* 排序
order gvkey fyear match_pair_id match_year match_industry treat is_treatment
sort match_pair_id is_treatment

* 保存结果
save "psm_sample9/PSM_same_year_industry.dta", replace

di ""
di "========================================="
di "匹配完成！"
di "========================================="
qui count
di "最终观测数: " r(N)
qui tab match_pair_id
di "匹配对数: " r(r)

*------------------------------------------------------------------------------
* 第四步：质量检验
*------------------------------------------------------------------------------

di ""
di "========================================="
di "质量检验"
di "========================================="

* 检验1: 控制组唯一性
preserve
keep if treat == 0
bys gvkey: gen n_used = _N
qui sum n_used
di "检验1: 控制组使用次数"
di "  最小值: " r(min) "  最大值: " r(max) "  平均: " r(mean)
if r(max) > 1 {
    di "  ⚠ 警告: 存在被多次使用的控制组"
    list gvkey match_year if n_used > 1
}
else {
    di "  ✓ 通过：所有控制组仅使用一次"
}
restore

* 检验2: 配对结构
preserve
collapse (sum) n_treat=is_treatment (count) pair_size=gvkey, by(match_pair_id)
gen n_control = pair_size - n_treat
di ""
di "检验2: 匹配对结构"
qui count if n_treat != 1 | n_control != 1
if r(N) > 0 {
    di "  ⚠ 警告: 存在配对不正确的匹配对"
}
else {
    di "  ✓ 通过：所有匹配对均为1:1结构"
}
restore

* 检验3: 年份分布
di ""
di "检验3: 各年份匹配情况"
tab match_year if treat == 1

* 检验4: 行业分布
di ""
di "检验4: 各行业匹配情况"
tab match_industry if treat == 1

* 检验5: 同年度验证
di ""
di "检验5: 同年度匹配验证"
bys match_pair_id: egen check_same_year = sd(fyear)
qui sum check_same_year
if r(max) == 0 {
    di "  ✓ 通过：所有匹配对在同一年度"
}
else {
    di "  ⚠ 警告: 存在跨年度匹配"
}
drop check_same_year

* 检验6: 同行业验证
di ""
di "检验6: 同行业匹配验证"
bys match_pair_id: egen check_same_ind = sd(`ind_var')
qui sum check_same_ind
if r(max) == 0 {
    di "  ✓ 通过：所有匹配对在同一行业"
}
else {
    di "  ⚠ 警告: 存在跨行业匹配"
}
drop check_same_ind

* 检验7: 协变量平衡性
di ""
di "检验7: 协变量平衡性（t检验）"
foreach var in size xrd_at q roa {
    qui ttest `var', by(treat)
    di "  `var': t=" %6.3f r(t) "  p=" %6.4f r(p)
}

di ""
di "========================================="
di "数据已保存至:"
di "psm_sample9/PSM_same_year_industry.dta"
di "========================================="
di ""
di "特点："
di "✓ 只包含事件年度数据（无时间窗口）"
di "✓ 同年度匹配"
di "✓ 同行业匹配"
di "✓ 1:1匹配且控制组不重复"
di ""
