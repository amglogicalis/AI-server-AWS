import os

IGNORE = {
    ".git",
    "node_modules",
    "venv",
    ".venv",
    "__pycache__",
    "dist",
    "build",
    ".idea",
    ".vscode",
    ".next",
    "target"
}

MAX_DEPTH = 5  # Pon None si quieres ilimitado

BLUE = "\033[94m"
RESET = "\033[0m"


def print_tree(path=".", prefix="", depth=0):
    if MAX_DEPTH is not None and depth > MAX_DEPTH:
        return

    try:
        entries = sorted(
            [e for e in os.scandir(path) if e.name not in IGNORE],
            key=lambda e: (not e.is_dir(follow_symlinks=False), e.name.lower())
        )
    except PermissionError:
        print(prefix + "└── [Permission denied]")
        return
    except Exception as e:
        print(prefix + f"└── [Error: {e}]")
        return

    total = len(entries)

    for i, entry in enumerate(entries):
        is_last = i == total - 1
        connector = "└── " if is_last else "├── "

        if entry.is_dir(follow_symlinks=False):
            print(prefix + connector + f"{BLUE}{entry.name}/{RESET}")
            extension = "    " if is_last else "│   "
            print_tree(entry.path, prefix + extension, depth + 1)
        else:
            print(prefix + connector + entry.name)


if __name__ == "__main__":
    root = os.path.abspath(".")
    print(root)
    print_tree(root)