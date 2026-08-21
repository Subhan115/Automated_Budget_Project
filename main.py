import os
import stat
import subprocess
import sys

# List of scripts in exact execution order
SCRIPTS = [
    "budget.sh",
    "action_group.sh",
    "notification.sh",
    "deploy_LogicApp.sh",
    "Logic_App_URL.sh",
    "RBAC.sh",
]

def make_executable(file_path: str) -> None:
    """Grant execute permissions (chmod +x) to the file."""
    current_stat = os.stat(file_path)
    os.chmod(file_path, current_stat.st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)

def main():
    for script in SCRIPTS:
        if not os.path.isfile(script):
            print(f"[ERROR] '{script}' does not exist in the current directory.")
            sys.exit(1)

        # 1. Grant permissions
        make_executable(script)
        print(f"[INFO] Granted execute permission: {script}")

        # 2. Run script sequentially
        print(f"[EXEC] Running {script}...")
        try:
            # check=True stops execution immediately if a script returns a non-zero exit code
            subprocess.run([f"./{script}"], check=True)
            print(f"[SUCCESS] Finished {script}\n")
        except subprocess.CalledProcessError as e:
            print(f"[ERROR] Execution failed for '{script}' with exit code {e.returncode}.")
            sys.exit(e.returncode)

    print("All deployment scripts completed successfully!")

if __name__ == "__main__":
    main()
