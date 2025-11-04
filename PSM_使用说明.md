# Year-by-Year 1:1 PSM 修正版使用说明

## 问题诊断

您原代码的主要问题：

### 🔴 问题1：控制组重复匹配
- **原因**：每年PSM时都使用完整的`samplefull_final.dta`
- **后果**：同一个控制组公司可能在2005年匹配给公司A，2008年又匹配给公司B
- **影响**：实际上不是1:1匹配，控制组被过度使用

### 🔴 问题2：匹配对追踪不准确
```stata
qui keep _n*
qui rename _n* n_n*
```
这段代码试图提取`_n1, _n2...`，但`n(1)`匹配只产生`_n1`。如果有`_n2`等，说明匹配逻辑有问题。

### 🔴 问题3：面板数据重复
在构建前后5年数据时，没有正确去重，导致同一个gvkey-fyear组合可能出现多次。

---

## 解决方案

### ✅ 核心改进

1. **防止重复匹配**
   - 维护`used_controls`临时文件，记录所有已被使用的控制组
   - 每次PSM前排除已使用的控制组

2. **准确的配对追踪**
   - 为每个匹配对分配唯一ID：`1000*年份 + 配对序号`
   - 使用`_n1`变量准确提取第一个匹配的control

3. **严格的数据结构验证**
   - 检查每个pair_id是否恰好包含2个观测（1个treatment + 1个control）
   - 检查每个控制组gvkey是否只出现一次

---

## 使用步骤

### 步骤1：准备环境

确保您的Stata安装了以下命令：
```stata
ssc install psmatch2
ssc install pstest
```

### 步骤2：在本地运行

由于当前环境没有Stata和数据文件，请：

1. 将 `PSM_year_by_year_corrected.do` 下载到本地
2. 在Stata中设置工作目录：
   ```stata
   cd "/Users/chupei/CTO_Prediction_Analysis-GEMINI/data/inter_data"
   ```
3. 运行脚本：
   ```stata
   do PSM_year_by_year_corrected.do
   ```

### 步骤3：检查结果

脚本会自动进行4项质量检验：

#### ✓ 检验1：控制组唯一性
确认每个控制组只被使用一次：
```
检验1: 控制组使用次数统计
  最小值: 1  最大值: 1  平均: 1
  ✓ 通过：所有控制组仅使用一次
```

#### ✓ 检验2：配对结构
确认每个匹配对都是1:1：
```
检验2: 匹配对结构
  ✓ 通过：所有匹配对均为1:1结构
```

#### ✓ 检验3：年度分布
显示各年份成功匹配的数量。

#### ✓ 检验4：平衡性检验
显示treatment和control组的协变量是否平衡。

---

## 预期输出

### 1. 数据文件
- `psm_sample9/PSM_5y_corrected.dta` - 最终匹配结果（包含前5年至后2年）

### 2. 关键变量

| 变量名 | 说明 |
|--------|------|
| `match_pair_id` | 匹配对唯一ID |
| `match_year` | 匹配发生的年份（事件年） |
| `treat` | =1表示treatment组，=0表示control组 |
| `Post` | =1表示事件后，=0表示事件前 |
| `D` | DID交互项 = treat × Post |
| `t` | 相对事件年的时间（-5到+2） |
| `is_treatment` | 在事件年是否为treatment |

### 3. 图表
- `psm_sample9/psm_corrected_density.png` - 倾向得分密度图

---

## 后续分析

### 1. 平行趋势检验
```stata
use "psm_sample9/PSM_5y_corrected.dta", clear

* 生成时间虚拟变量（以t=-1为基准）
xi i.t, prefix(T_)
drop T_t_5  // 基准组

* 平行趋势检验
reghdfe Inv treat##(T_t_6 T_t_4 T_t_3 T_t_2 T_t_1 T_t0 T_t1 T_t2) ///
    size xrd_at q roa, absorb(gvkey fyear) cluster(gvkey)

* 绘制系数图
coefplot, keep(1.treat#*T_t*) vertical yline(0) ///
    title("Parallel Trend Test") xtitle("Event Time")
```

### 2. DID回归
```stata
* 基准回归
reghdfe Inv D treat Post size xrd_at q roa, ///
    absorb(gvkey fyear) cluster(gvkey)

* 稳健性检验：不同因变量
foreach dv in Capx deltaTA CapxXrd Itotal {
    reghdfe `dv' D treat Post size xrd_at q roa, ///
        absorb(gvkey fyear) cluster(gvkey)
}
```

### 3. 安慰剂检验
```stata
* 使用事件前的假treatment时点
preserve
keep if t < 0
gen fake_Post = (t >= -3)  // 假设在t=-3发生事件
gen fake_D = treat * fake_Post
reghdfe Inv fake_D treat fake_Post size xrd_at q roa, ///
    absorb(gvkey fyear) cluster(gvkey)
restore
```

---

## 常见问题

### Q1: 为什么有些年份匹配数量很少？
**A**: 可能原因：
1. 该年份treatment样本少
2. 可用的控制组被之前年份用完了
3. 协变量差异太大，在卡尺范围内找不到匹配

**建议**：考虑放宽卡尺（从0.05改为0.1），或使用更灵活的匹配比例。

### Q2: 如果我想要1:3或1:5匹配怎么办？
**A**: 修改两处：
1. `psmatch2`命令中的`n(1)`改为`n(3)`或`n(5)`
2. 在提取匹配结果时，需要循环处理`_n1, _n2, _n3...`

### Q3: 卡尺设置多少合适？
**A**:
- 0.01：非常严格，匹配数量少但质量高
- 0.05：标准设置（推荐）
- 0.10：较宽松，匹配数量多但可能牺牲平衡性

### Q4: 如何处理缺失值？
**A**: 脚本已包含缺失值处理，但您也可以：
1. 事先插补缺失值
2. 使用不同的协变量组合
3. 检查缺失值模式是否与treatment相关

---

## 对比原代码

| 方面 | 原代码 | 修正后代码 |
|------|--------|------------|
| 控制组使用 | 可重复使用 | 只使用一次 ✓ |
| 匹配对追踪 | 不准确 | 唯一ID追踪 ✓ |
| 数据去重 | 最后去重 | 每步验证 ✓ |
| 质量检验 | 无 | 4项自动检验 ✓ |
| 代码效率 | 中等 | 优化 ✓ |

---

## 技术支持

如果遇到问题，请检查：

1. **数据路径**：确保`samplefull_final.dta`存在
2. **变量名称**：确认数据中有`size, xrd_at, q, roa`等变量
3. **输出目录**：确保`psm_sample9`文件夹存在或脚本有权限创建
4. **Stata版本**：建议使用Stata 15或更高版本

运行中的任何错误信息，请提供完整的错误日志以便诊断。

---

**创建日期**: 2025-11-04
**版本**: 1.0
**作者**: Claude Code Assistant
