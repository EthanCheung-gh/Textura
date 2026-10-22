# 字体资产

parity 固定字体：**Noto Sans CJK SC**。

## 本机文件

```text
/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc
sha256 b76b0433203017ca80401b2ee0dd69350349871c4b19d504c34dbdd80541690a
size   19 MiB
```

TTC face 顺序（`fc-scan` 验证）：

| index | family |
|---:|---|
| 0 | Noto Sans CJK JP |
| 1 | Noto Sans CJK KR |
| 2 | **Noto Sans CJK SC** |
| 3 | Noto Sans CJK TC |
| 4 | Noto Sans CJK HK |
| 5..9 | Noto Sans Mono CJK JP/KR/SC/TC/HK |

## 为什么没有把 19 MiB TTC 提交进仓库

- 字体是系统包（Ubuntu `fonts-noto-cjk`），本机固定路径即可复现。
- parity 脚本启动前会检查 `fc-match 'Noto Sans CJK SC'`；缺失时直接报错，不会静默换字体。
- 如果后续要脱离系统字体（CI / 鸿蒙），把字体放到本目录并在 `Fonts.registerFamily` 里用
  `FontSource("assets/fonts/NotoSansCJK-Regular.ttc", faceIndex: 2)` 注册；许可证为 SIL OFL 1.1，需同时保留 `LICENSE`。

## 校验

```bash
fc-match 'Noto Sans CJK SC'
sha256sum /usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc
```

CUI 侧设置：

```cangjie
Fonts.setDefault("Noto Sans CJK SC")
// 或显式 TTC face：
Fonts.registerFamily("Textura UI", FontFamily(
    FontSource("/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc", faceIndex: 2)
))
Fonts.setDefault("Textura UI")
```
