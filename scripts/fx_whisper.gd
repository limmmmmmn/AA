class_name WhisperFX
extends RichTextEffect
## [whisper]…일단은.[/whisper] — 축소 + 저채도의 속삭임 (v3.7 §E)

var bbcode := "whisper"

func _process_custom_fx(c: CharFXTransform) -> bool:
	c.transform = c.transform.scaled_local(Vector2(0.85, 0.85))
	c.color = c.color.lerp(Color("8b8fa3"), 0.55)
	c.color.a *= 0.85
	return true
