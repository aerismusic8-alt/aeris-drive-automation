from pathlib import Path
import importlib.util
import tempfile

MODULE = Path(__file__).resolve().parents[1] / "runtime" / "ax_openai_code_writer.py"
spec = importlib.util.spec_from_file_location("ax_openai_code_writer", MODULE)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


def test_extract_code_accepts_fenced_python():
    text = "before\n```python\nprint('ok')\n```\nafter"
    assert mod.extract_code(text) == "print('ok')\n"


def test_stream_lines_writes_real_lines_to_writer():
    events = []
    mod.emit = lambda *args, **kwargs: events.append((args, kwargs))
    mod.stream_code("print('a')\nprint('b')\n", "TASK-1", "demo.py")
    assert events[0][0][0:4] == ("OPENAI", "TASK-1", "demo.py", "START")
    assert events[1][0][3] == "LINE"
    assert events[2][0][3] == "LINE"
    assert events[-1][0][3] == "END"
