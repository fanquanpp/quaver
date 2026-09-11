extends Node
## 临时脚本：为 README 重拍界面截图（演奏页 + 编曲页），拍完删除


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var ps: PackedScene = load("res://scenes/main.tscn")
	var ui: Control = ps.instantiate()
	add_child(ui)
	# 等音源合成 + 首帧渲染
	await get_tree().create_timer(5.0).timeout
	ui._on_demo()  # 载入《虫儿飞》完整示范曲
	DisplayServer.window_set_size(Vector2i(1280, 768))
	await get_tree().create_timer(1.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://docs/screenshots/play.png")
	# 编曲页
	ui.tabs.current_tab = 1
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://docs/screenshots/arrange.png")
	get_tree().quit(0)
