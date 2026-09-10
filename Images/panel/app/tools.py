import subprocess

def run(cmd, cwd=None):
    try:
        result = subprocess.run(cmd, cwd=cwd, check=True, capture_output=True, text=True)
    except Exception as e:
        return ["fail", str(e)]
    return ["ok", result.stdout]