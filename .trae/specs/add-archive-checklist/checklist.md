# Checklist

- [x] `files` 表包含 `archived`、`archived_parent_id`、`archived_path` 字段，旧数据默认未归档
- [x] `POST /api/files/{id}/archive` 能归档文件：记录原路径、`parent_id` 置空、返回文件元数据
- [x] `POST /api/files/{id}/restore` 不带 `target_folder_id` 时恢复原处；原路径不存在时返回可读错误
- [x] `POST /api/files/{id}/restore` 携带 `target_folder_id` 时移动到目标文件夹并清除归档状态
- [x] `GET /api/archive` 返回所有已归档文件及归档时路径，按归档时间倒序
- [x] `GET /api/folders/tree` 与子级列表不返回已归档文件
- [x] `FileMetaResponse` / `FileResponse` 返回 `todo_total`、`todo_done`，且统计结果与 `content` 中 `- [ ]`/`- [x]` 一致
- [x] iOS 设置页存在「归档」入口并能进入归档列表
- [x] iOS 归档列表展示归档笔记名称与归档时路径
- [x] iOS 归档项可「恢复到原处」与「移动到...」；原路径不存在时弹窗提示并引导选择其它路径
- [x] iOS 笔记详情查看模式下 `- [ ]`/`- [x]` 以复选框展示，点击勾选/取消后内容保存
- [x] iOS 编辑模式支持 checklist 勾选，且编辑工具条有「清单」按钮可插入 `- [x] `
- [x] iOS 笔记列表 item 右下角展示「完成/总数」，仅 `todo_total > 0` 时显示
- [x] 全部 checklist 完成后弹窗「已完成全部，是否移入归档」，选择「移入归档」执行归档
- [x] iOS 进入笔记详情页时隐藏底部 Tab 栏，返回列表恢复显示
