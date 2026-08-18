from scripts.check_secrets import scan_text


def test_empty_secret_lines_do_not_consume_following_line():
    text = "LIVEKIT_API_KEY=\nLIVEKIT_API_SECRET=\nGROQ_API_KEY=\n"
    assert scan_text(text, location="example") == []


def test_placeholder_secret_values_are_ignored():
    text = "GROQ_API_KEY=<replace-me>\nLIVEKIT_API_SECRET=changeme\n"
    assert scan_text(text, location="example") == []


def test_non_placeholder_assignment_is_detected_without_echoing_value():
    value = "opaque-value-123456789"
    text = f"GROQ_API_KEY={value}\n"
    findings = scan_text(text, location="example")

    assert findings == ["example: non-placeholder value assigned to GROQ_API_KEY"]
    assert value not in findings[0]


def test_credential_shaped_groq_material_is_detected_without_echoing_value():
    prefix = "g" + "sk_"
    value = prefix + "abcdefghijklmnopqrstuvwxyz012345"
    findings = scan_text(f"note={value}\n", location="history")

    assert findings == ["history: credential-shaped material detected"]
    assert value not in findings[0]
