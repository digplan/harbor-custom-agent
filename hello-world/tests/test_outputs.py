"""
Verify that the agent created /app/hello.txt containing "Hello, world!".

This file is copied to /tests/test_outputs.py and run by /tests/test.sh.
"""


def test_hello_file_exists_and_matches():
    path = "/app/hello.txt"
    with open(path) as f:
        content = f.read().strip()
    assert content == "Hello, world!", f"Expected 'Hello, world!', got {content!r}"