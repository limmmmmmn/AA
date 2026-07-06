class_name SlamFX
extends RichTextEffect
## [slam]단어[/slam] — 쿵 하고 커졌다가 제자리에 정착 (v3.7 §E — "…참치다.")

var bbcode := "slam"

func _process_custom_fx(c: CharFXTransform) -> bool:
	var t := clampf(c.elapsed_time * 4.0, 0.0, 1.0)
	# 2.4배 → 1.0배, 살짝 오버슈트
	var s := 2.4 - 1.4 * t
	if t > 0.85:
		s = 1.0 + 0.15 * sin((1.0 - t) * 20.0)
	c.transform = c.transform.scaled_local(Vector2(s, s))
	# 착지 직전까지는 반투명 — 쿵 순간에 선명해진다
	c.color.a = minf(1.0, 0.4 + t * 0.8)
	return true
