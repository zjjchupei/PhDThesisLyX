*=======================================================================================
* 快速修复：变量名称问题
*=======================================================================================
* 问题：您的数据中可能没有某些变量（如MtB）
* 解决方案：只保留核心必需变量，其他变量自动包含
*=======================================================================================

* 方案1：检查您的数据中有哪些变量
use "/Users/chupei/CTO_Prediction_Analysis-GEMINI/data/inter_data/samplefull_final.dta", clear
describe
* 请找到market-to-book ratio的实际变量名，可能是：
* - mtb (小写)
* - MB
* - MtoB
* - q (Tobin's Q)

* 然后用正确的变量名替换下面代码中的 MtB

*=======================================================================================
* 方案2：使用修改后的merge命令（推荐）
*=======================================================================================
* 把原脚本第266-267行的：
*
* merge m:1 gvkey fyear using `master_data', ///
*     keep(3) nogen ///
*     keepusing(cto_event size xrd_at q roa cash leverage MtB dividends ///
*              liquiR Pastprof quick_ratio rd_sale Inv Capx deltaTA CapxXrd Itotal Inew)
*
* 改为以下两种之一：

* 选项A：不指定keepusing，保留所有变量（简单但可能有多余变量）
* merge m:1 gvkey fyear using `master_data', keep(3) nogen

* 选项B：只保留肯定存在的核心变量
* merge m:1 gvkey fyear using `master_data', ///
*     keep(3) nogen ///
*     keepusing(cto_event size xrd_at q roa)

*=======================================================================================
* 方案3：一键式修复脚本
*=======================================================================================
* 运行下面的命令来生成修复后的do文件

! sed 's/keepusing(cto_event size xrd_at q roa cash leverage MtB dividends.*Inew)//' \
    PSM_year_by_year_corrected.do > PSM_year_by_year_fixed.do

* 或者使用这个更安全的版本：
