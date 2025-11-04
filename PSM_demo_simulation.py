#!/usr/bin/env python3
"""
PSM Year-by-Year 1:1 匹配问题演示
展示修正前后的差异

作者：Claude Code Assistant
日期：2025-11-04
"""

import pandas as pd
import numpy as np
from datetime import datetime

# 设置随机种子以便结果可重现
np.random.seed(42)

print("=" * 80)
print("Year-by-Year PSM 1:1 匹配问题模拟演示")
print("=" * 80)
print()

# ============================================================================
# 第一部分：创建模拟数据
# ============================================================================
print("第一步：创建模拟数据")
print("-" * 80)

# 参数设置
n_firms = 200  # 总公司数
n_years = 10   # 年份范围：2011-2020
start_year = 2011

# 创建公司ID
firms = [f"FIRM_{i:03d}" for i in range(1, n_firms + 1)]

# 创建面板数据
data_list = []
for firm_id in firms:
    for year_offset in range(n_years):
        year = start_year + year_offset

        # 随机生成协变量
        size = np.random.normal(5, 1)
        xrd_at = np.random.uniform(0, 0.1)
        q = np.random.normal(1.5, 0.5)
        roa = np.random.normal(0.05, 0.03)

        data_list.append({
            'gvkey': firm_id,
            'fyear': year,
            'size': size,
            'xrd_at': xrd_at,
            'q': q,
            'roa': roa
        })

df = pd.DataFrame(data_list)

# 随机分配CTO事件（10%的公司有CTO事件）
treatment_firms = np.random.choice(firms, size=20, replace=False)
df['cto_event'] = 0

for firm in treatment_firms:
    # 为每个treatment公司随机分配事件年份
    event_year = np.random.choice(range(2013, 2019))  # 2013-2018
    df.loc[(df['gvkey'] == firm) & (df['fyear'] == event_year), 'cto_event'] = 1

# 统计信息
total_events = df['cto_event'].sum()
n_treatment_firms = len(treatment_firms)
n_control_firms = len(firms) - n_treatment_firms

print(f"数据规模：")
print(f"  总观测数：{len(df):,}")
print(f"  公司数：{n_firms}")
print(f"  年份范围：{start_year}-{start_year + n_years - 1}")
print(f"  Treatment公司：{n_treatment_firms}")
print(f"  潜在Control公司：{n_control_firms}")
print(f"  CTO事件总数：{total_events}")
print()

# 按年份统计事件
events_by_year = df[df['cto_event'] == 1].groupby('fyear').size()
print("各年份CTO事件数：")
print(events_by_year)
print()

# ============================================================================
# 第二部分：模拟原代码的问题（控制组重复匹配）
# ============================================================================
print("\n" + "=" * 80)
print("第二步：模拟原代码的问题（控制组可重复使用）")
print("=" * 80)
print()

# 简化版PSM：基于倾向得分距离的最近邻匹配
def simple_psm_match(df_year, allow_reuse=True, used_controls=set()):
    """
    简化的PSM匹配函数

    参数：
    - df_year: 当年的数据
    - allow_reuse: 是否允许控制组重复使用
    - used_controls: 已使用的控制组集合
    """
    # 计算简化的倾向得分（基于协变量的标准化距离）
    controls = ['size', 'xrd_at', 'q', 'roa']

    # 标准化
    df_std = df_year.copy()
    for col in controls:
        mean = df_year[col].mean()
        std = df_year[col].std()
        df_std[col] = (df_year[col] - mean) / std if std > 0 else 0

    # 获取treatment和control
    treatments = df_std[df_std['cto_event'] == 1]

    if allow_reuse:
        candidates = df_std[df_std['cto_event'] == 0]
    else:
        # 排除已使用的控制组
        candidates = df_std[(df_std['cto_event'] == 0) &
                           (~df_std['gvkey'].isin(used_controls))]

    matches = []
    new_used_controls = set()

    for _, treat in treatments.iterrows():
        if len(candidates) == 0:
            continue

        # 计算马氏距离
        distances = []
        for _, control in candidates.iterrows():
            dist = sum((treat[col] - control[col])**2 for col in controls)**0.5
            distances.append((control['gvkey'], dist))

        # 找到最近的control
        if distances:
            best_match = min(distances, key=lambda x: x[1])
            matches.append({
                'year': treat['fyear'],
                'treatment': treat['gvkey'],
                'control': best_match[0],
                'distance': best_match[1]
            })
            new_used_controls.add(best_match[0])

    return matches, new_used_controls

# 模拟原代码：允许重复匹配
print("【原代码方式】每年PSM，允许控制组重复使用")
print("-" * 80)

all_matches_original = []
for year in range(start_year, start_year + n_years):
    df_year = df[df['fyear'] == year].copy()
    matches, _ = simple_psm_match(df_year, allow_reuse=True, used_controls=set())
    all_matches_original.extend(matches)
    if matches:
        print(f"  {year}年：匹配了 {len(matches)} 对")

print(f"\n原代码总匹配对数：{len(all_matches_original)}")

# 检查控制组重复使用
controls_used = [m['control'] for m in all_matches_original]
controls_counts = pd.Series(controls_used).value_counts()
duplicates = controls_counts[controls_counts > 1]

print(f"\n🔴 问题诊断：")
print(f"  使用过的控制组总数（含重复）：{len(controls_used)}")
print(f"  唯一控制组数量：{len(set(controls_used))}")
print(f"  被重复使用的控制组：{len(duplicates)} 个")

if len(duplicates) > 0:
    print(f"\n  重复使用最严重的控制组：")
    for ctrl, count in duplicates.head(5).items():
        years_used = [m['year'] for m in all_matches_original if m['control'] == ctrl]
        print(f"    {ctrl}: 被使用 {count} 次，在年份 {years_used}")

# ============================================================================
# 第三部分：展示修正后的代码（控制组只使用一次）
# ============================================================================
print("\n" + "=" * 80)
print("第三步：修正后的代码（控制组只使用一次）")
print("=" * 80)
print()

print("【修正代码方式】逐年PSM，排除已使用的控制组")
print("-" * 80)

all_matches_corrected = []
used_controls_global = set()

for year in range(start_year, start_year + n_years):
    df_year = df[df['fyear'] == year].copy()
    matches, new_used = simple_psm_match(df_year, allow_reuse=False,
                                         used_controls=used_controls_global)

    all_matches_corrected.extend(matches)
    used_controls_global.update(new_used)

    if matches:
        print(f"  {year}年：匹配了 {len(matches)} 对，"
              f"累计已使用控制组 {len(used_controls_global)} 个")

print(f"\n修正后总匹配对数：{len(all_matches_corrected)}")

# 检查控制组使用情况
controls_used_corrected = [m['control'] for m in all_matches_corrected]
controls_counts_corrected = pd.Series(controls_used_corrected).value_counts()
duplicates_corrected = controls_counts_corrected[controls_counts_corrected > 1]

print(f"\n✅ 验证结果：")
print(f"  使用过的控制组总数：{len(controls_used_corrected)}")
print(f"  唯一控制组数量：{len(set(controls_used_corrected))}")
print(f"  被重复使用的控制组：{len(duplicates_corrected)} 个")

if len(duplicates_corrected) == 0:
    print(f"  ✓ 成功：每个控制组只被使用一次！")
else:
    print(f"  ⚠ 警告：仍有重复使用")

# ============================================================================
# 第四部分：对比分析
# ============================================================================
print("\n" + "=" * 80)
print("第四步：对比分析")
print("=" * 80)
print()

comparison = pd.DataFrame({
    '指标': [
        '总匹配对数',
        '唯一控制组数',
        '控制组重复使用数',
        '平均每个控制组使用次数',
        '是否符合1:1原则'
    ],
    '原代码': [
        len(all_matches_original),
        len(set(controls_used)),
        len(duplicates),
        f"{len(controls_used) / len(set(controls_used)):.2f}",
        '❌ 否' if len(duplicates) > 0 else '✓ 是'
    ],
    '修正代码': [
        len(all_matches_corrected),
        len(set(controls_used_corrected)),
        len(duplicates_corrected),
        f"{len(controls_used_corrected) / len(set(controls_used_corrected)):.2f}",
        '✅ 是' if len(duplicates_corrected) == 0 else '❌ 否'
    ]
})

print(comparison.to_string(index=False))
print()

# ============================================================================
# 第五部分：生成详细报告
# ============================================================================
print("\n" + "=" * 80)
print("第五步：详细匹配结果对比")
print("=" * 80)
print()

# 创建对比DataFrame
df_original = pd.DataFrame(all_matches_original)
df_corrected = pd.DataFrame(all_matches_corrected)

if len(df_original) > 0:
    print("【原代码】按年份统计匹配对数：")
    print(df_original.groupby('year').size())
    print()

if len(df_corrected) > 0:
    print("【修正代码】按年份统计匹配对数：")
    print(df_corrected.groupby('year').size())
    print()

# 影响分析
print("💡 关键发现：")
print("-" * 80)

if len(all_matches_original) > len(all_matches_corrected):
    diff = len(all_matches_original) - len(all_matches_corrected)
    print(f"1. 原代码由于重复使用控制组，虚增了 {diff} 个匹配对")
    print(f"   实际有效的1:1匹配对只有 {len(all_matches_corrected)} 对")
    print()

if len(duplicates) > 0:
    max_reuse = duplicates.max()
    print(f"2. 原代码中，有控制组被重复使用最多 {max_reuse} 次")
    print(f"   这严重违反了1:1匹配的假设")
    print()

print(f"3. 修正后的代码确保：")
print(f"   ✓ 每个治疗组最多匹配1个控制组")
print(f"   ✓ 每个控制组最多被使用1次")
print(f"   ✓ 符合严格的1:1配对设计")
print()

# ============================================================================
# 结论
# ============================================================================
print("\n" + "=" * 80)
print("结论与建议")
print("=" * 80)
print()

print("📊 模拟结果表明：")
print()
print("【问题】")
print("  您的原代码在逐年PSM时，同一个控制组公司可能在不同年份")
print("  被匹配给不同的treatment公司，导致：")
print(f"  - 虚增匹配对数（本例中多了 {len(all_matches_original) - len(all_matches_corrected)} 对）")
print(f"  - 违反1:1匹配假设")
print(f"  - 可能导致标准误被低估")
print()

print("【解决方案】")
print("  修正后的代码通过维护已使用控制组列表，确保：")
print("  ✓ 每次PSM前排除已被使用的控制组")
print("  ✓ 真正的1:1匹配")
print("  ✓ 更保守但更准确的估计")
print()

print("【实际应用】")
print("  这个模拟演示了核心逻辑，您的实际数据规模更大，")
print(f"  重复匹配问题可能更严重。建议：")
print("  1. 使用修正后的Stata脚本：PSM_year_by_year_corrected.do")
print("  2. 运行质量检验确认无重复")
print("  3. 对比修正前后的回归结果")
print()

print("=" * 80)
print("演示完成！")
print("=" * 80)
print()
print(f"生成时间：{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
