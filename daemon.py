#!/usr/bin/env python3
"""
Sashframe - Parent Production Supervisor Daemon (Legacy Fallback)

[DEPRECATION NOTICE]
Docker Compose is now the primary production supervisor for Sashframe:
  docker compose up -d
  docker compose ps
  docker compose logs -f
  docker compose down

This script is retained for backwards compatibility and local standalone testing
without Docker.
"""

from __future__ import annotations

import argparse
from datetime import datetime
import json
import logging
import os
from pathlib import Path
import select
import shutil
import signal
import socket
import subprocess
import sys
import threading
import time
from typing import Optional

def load_env_file(path: Path) -> None:
    """Load key-value environment variables from file if present and not already set."""
    if not path.is_file():
        return
    try:
        with open(path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                k, v = line.split("=", 1)
                k = k.strip()
                v = v.strip().strip("'\"")
                if k not in os.environ:
                    os.environ[k] = v
    except Exception:
        pass


load_env_file(Path("/etc/sashframe/sashframe.env"))

# Base Paths
REPO_ROOT = Path(__file__).resolve().parent
DATA_DIR = REPO_ROOT / "data"
PID_FILE = DATA_DIR / "daemon.pid"
LOG_FILE = DATA_DIR / "daemon.log"
INSTALL_SCRIPT = REPO_ROOT / "scripts" / "install.sh"
PHOTO_PROCESSOR = REPO_ROOT / "services" / "photos" / "processor.py"
DIST_DIR = REPO_ROOT / "dist"
DIST_INDEX = DIST_DIR / "index.html"
MANIFEST_PATH = Path(os.environ.get("PHOTO_MANIFEST", DATA_DIR / "photos" / "manifest.json"))
INCOMING_DIR = Path(os.environ.get("PHOTO_INPUT_DIR", DATA_DIR / "photos" / "incoming"))
PROCESSED_DIR = Path(os.environ.get("PHOTO_OUTPUT_DIR", DATA_DIR / "photos" / "processed"))

VENV_DIR = REPO_ROOT / ".venv"
VENV_PYTHON = VENV_DIR / "bin" / "python3"
NODE_MODULES = REPO_ROOT / "node_modules"
ASTRO_BIN = NODE_MODULES / ".bin" / "astro"

# Setup root logger
logger = logging.getLogger("sashframe.daemon")


def setup_logging(to_console: bool = True, log_file: Optional[Path] = None) -> None:
    """Configure structured logging for daemon and supervised child processes."""
    logger.setLevel(logging.INFO)
    logger.handlers.clear()

    formatter = logging.Formatter(
        "%(asctime)s [%(levelname)s] [Daemon] %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )

    if to_console:
        ch = logging.StreamHandler(sys.stdout)
        ch.setFormatter(formatter)
        logger.addHandler(ch)

    if log_file:
        log_file.parent.mkdir(parents=True, exist_ok=True)
        fh = logging.FileHandler(log_file, encoding="utf-8")
        fh.setFormatter(formatter)
        logger.addHandler(fh)


# ----------------------------------------------------------------------
# 1. Verification & Self-Healing
# ----------------------------------------------------------------------

def is_install_complete() -> tuple[bool, list[str]]:
    """
    Check if scripts/install.sh has been run and all prerequisites exist.
    Returns (is_valid, list_of_missing_items).
    """
    missing = []

    # Check python virtual environment
    if not VENV_DIR.is_dir() or not VENV_PYTHON.is_file():
        missing.append("Python virtual environment (.venv/bin/python3)")
    else:
        # Check required python packages inside venv
        test_cmd = [str(VENV_PYTHON), "-c", "import watchdog, PIL"]
        try:
            res = subprocess.run(test_cmd, capture_output=True, timeout=5)
            if res.returncode != 0:
                missing.append("Python dependencies (watchdog, Pillow)")
        except Exception:
            missing.append("Python dependencies probe failed")

    # Check node modules and astro binary
    if not NODE_MODULES.is_dir() or not ASTRO_BIN.is_file():
        missing.append("Node modules (node_modules/.bin/astro)")

    return len(missing) == 0, missing


def verify_installation(auto_install: bool = True) -> bool:
    """
    Verify installation state. If missing components and auto_install is True,
    runs scripts/install.sh automatically.
    """
    is_valid, missing = is_install_complete()
    if is_valid:
        logger.info("Environment verification passed: all dependencies and runtimes verified.")
        return True

    logger.warning("Environment verification found missing components: %s", ", ".join(missing))

    if not auto_install:
        logger.error("Auto-install disabled. Please run 'bash scripts/install.sh' first.")
        return False

    if not INSTALL_SCRIPT.is_file():
        logger.error("Install script not found at %s", INSTALL_SCRIPT)
        return False

    logger.info("Running installation script (%s)...", INSTALL_SCRIPT)
    try:
        proc = subprocess.Popen(
            ["bash", str(INSTALL_SCRIPT)],
            cwd=str(REPO_ROOT),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )

        for line in proc.stdout:  # type: ignore
            clean = line.rstrip()
            if clean:
                logger.info("[Install] %s", clean)

        proc.wait()
        if proc.returncode != 0:
            logger.error("Installation script failed with exit code %d", proc.returncode)
            return False

        logger.info("Installation script completed successfully.")
    except Exception as e:
        logger.error("Failed to execute install script: %s", e)
        return False

    # Re-verify
    is_valid_after, missing_after = is_install_complete()
    if not is_valid_after:
        logger.error("Environment still incomplete after install: %s", ", ".join(missing_after))
        return False

    logger.info("Environment re-verification passed.")
    return True


def ensure_production_build(force_rebuild: bool = False) -> bool:
    """
    Verify that production bundle (dist/) exists. If missing or forced, runs build.
    """
    if DIST_INDEX.is_file() and not force_rebuild:
        logger.info("Production build bundle verified at dist/")
        return True

    action = "Rebuilding" if force_rebuild else "Building"
    logger.info("%s Astro production bundle (npm run build)...", action)

    try:
        proc = subprocess.Popen(
            ["npm", "run", "build"],
            cwd=str(REPO_ROOT),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )

        for line in proc.stdout:  # type: ignore
            clean = line.rstrip()
            if clean:
                logger.info("[Build] %s", clean)

        proc.wait()
        if proc.returncode != 0:
            logger.error("Production build failed with exit code %d", proc.returncode)
            return False

        if not DIST_INDEX.is_file():
            logger.error("Production build finished but dist/index.html is still missing.")
            return False

        logger.info("Production build complete and verified.")
        return True
    except Exception as e:
        logger.error("Failed to run build process: %s", e)
        return False


# ----------------------------------------------------------------------
# 2. Port & Conflicting Process Management
# ----------------------------------------------------------------------

def is_port_in_use(port: int, host: str = "127.0.0.1") -> bool:
    """Check if a network port is already in use."""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(0.5)
        return s.connect_ex((host, port)) == 0


def resolve_port_conflicts(port: int) -> None:
    """
    If port is in use or lockfiles exist, cleanly stop any conflicting
    astro dev or preview instances before starting production preview.
    """
    # Always attempt cleaning up existing background servers
    for cmd in [["npx", "astro", "dev", "stop"], ["npx", "astro", "preview", "stop"]]:
        try:
            subprocess.run(
                cmd,
                cwd=str(REPO_ROOT),
                capture_output=True,
                text=True,
                timeout=5,
            )
        except Exception:
            pass

    if is_port_in_use(port):
        logger.warning(
            "Port %d is currently occupied by an external process. Waiting for release...",
            port,
        )
        time.sleep(1.0)


# ----------------------------------------------------------------------
# 3. Supervised Process Runner
# ----------------------------------------------------------------------

class ManagedSubprocess:
    """Manages a single child process with log streaming and lifecycle controls."""

    def __init__(self, name: str, cmd: list[str], cwd: Path):
        self.name = name
        self.cmd = cmd
        self.cwd = cwd
        self.process: Optional[subprocess.Popen] = None
        self._reader_thread: Optional[threading.Thread] = None

    def start(self) -> None:
        """Start process in a new process group."""
        logger.info("Starting %s process: %s", self.name, " ".join(self.cmd))
        self.process = subprocess.Popen(
            self.cmd,
            cwd=str(self.cwd),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
            preexec_fn=os.setsid,  # Create distinct process group
        )

        self._reader_thread = threading.Thread(
            target=self._stream_logs,
            daemon=True,
            name=f"{self.name}-log-reader",
        )
        self._reader_thread.start()

    def _stream_logs(self) -> None:
        """Read and prefix stdout from child process."""
        if not self.process or not self.process.stdout:
            return
        try:
            for line in iter(self.process.stdout.readline, ""):
                clean = line.rstrip()
                if clean:
                    logger.info("[%s] %s", self.name, clean)
        except Exception:
            pass

    def is_running(self) -> bool:
        """Check if process is active."""
        if not self.process:
            return False
        return self.process.poll() is None

    def poll(self) -> Optional[int]:
        """Poll exit code."""
        if not self.process:
            return None
        return self.process.poll()

    def stop(self, timeout: float = 4.0) -> None:
        """Terminate process group gracefully, fallback to SIGKILL."""
        if not self.process or not self.is_running():
            return

        pid = self.process.pid
        logger.info("Stopping %s (PID %d)...", self.name, pid)
        try:
            pgid = os.getpgid(pid)
            os.killpg(pgid, signal.SIGTERM)
        except ProcessLookupError:
            return
        except Exception as e:
            logger.warning("Could not send SIGTERM to %s (PID %d): %s", self.name, pid, e)

        start_time = time.time()
        while self.is_running() and (time.time() - start_time) < timeout:
            time.sleep(0.1)

        if self.is_running():
            logger.warning("%s (PID %d) did not terminate gracefully; sending SIGKILL...", self.name, pid)
            try:
                pgid = os.getpgid(pid)
                os.killpg(pgid, signal.SIGKILL)
            except Exception:
                pass


# ----------------------------------------------------------------------
# 4. Supervisor Loop
# ----------------------------------------------------------------------

class DaemonSupervisor:
    """Coordinates and supervises all production services."""

    def __init__(self, host: str = "0.0.0.0", port: int = 4321):
        self.host = host
        self.port = port
        self.stop_requested = threading.Event()

        python_exec = str(VENV_PYTHON) if VENV_PYTHON.is_file() else sys.executable

        self.services = {
            "Photos": ManagedSubprocess(
                name="Photos",
                cmd=[python_exec, str(PHOTO_PROCESSOR)],
                cwd=REPO_ROOT,
            ),
            "Astro": ManagedSubprocess(
                name="Astro",
                cmd=["npx", "astro", "preview", "--host", self.host, "--port", str(self.port), "--ignore-lock"],
                cwd=REPO_ROOT,
            ),
        }

    def _setup_signal_handlers(self) -> None:
        """Handle termination signals cleanly."""
        def handler(signum, frame):
            sig_name = signal.Signals(signum).name
            logger.info("Received %s. Initiating graceful shutdown...", sig_name)
            self.stop_requested.set()

        signal.signal(signal.SIGINT, handler)
        signal.signal(signal.SIGTERM, handler)
        if hasattr(signal, "SIGHUP"):
            signal.signal(signal.SIGHUP, handler)

    def run(self) -> None:
        """Main supervisor loop."""
        self._setup_signal_handlers()

        logger.info("==================================================")
        logger.info(" Sashframe Production Daemon Starting")
        logger.info("==================================================")
        logger.info(" Host: %s | Port: %d", self.host, self.port)
        logger.info(" URL:  http://%s:%d", "localhost" if self.host == "0.0.0.0" else self.host, self.port)
        logger.info(" PID:  %d", os.getpid())

        # Start child processes
        for name, service in self.services.items():
            service.start()

        logger.info("All services initiated. Entering supervisor loop.")

        try:
            while not self.stop_requested.is_set():
                time.sleep(1.0)

                # Monitor and restart if any service crashed
                for name, service in self.services.items():
                    code = service.poll()
                    if code is not None and not self.stop_requested.is_set():
                        logger.error("Service [%s] terminated unexpectedly (exit code %d). Restarting in 2s...", name, code)
                        time.sleep(2.0)
                        if not self.stop_requested.is_set():
                            service.start()
        finally:
            self._shutdown()

    def _shutdown(self) -> None:
        """Stop all managed services and clean up PID file."""
        logger.info("Shutting down managed services...")
        for name, service in self.services.items():
            service.stop(timeout=4.0)

        if PID_FILE.is_file():
            try:
                PID_FILE.unlink()
            except OSError:
                pass

        logger.info("Sashframe Daemon shutdown complete.")


# ----------------------------------------------------------------------
# 5. Daemonization & PID Management
# ----------------------------------------------------------------------

def daemonize(pid_file: Path, log_file: Path) -> None:
    """Standard double-fork daemonization for Unix systems."""
    try:
        pid = os.fork()
        if pid > 0:
            sys.exit(0)  # Exit first parent
    except OSError as e:
        sys.stderr.write(f"Fork #1 failed: {e}\n")
        sys.exit(1)

    os.chdir(str(REPO_ROOT))
    os.setsid()
    os.umask(0)

    try:
        pid = os.fork()
        if pid > 0:
            sys.exit(0)  # Exit second parent
    except OSError as e:
        sys.stderr.write(f"Fork #2 failed: {e}\n")
        sys.exit(1)

    # Redirect standard file descriptors
    sys.stdout.flush()
    sys.stderr.flush()

    log_file.parent.mkdir(parents=True, exist_ok=True)
    dev_null = open(os.devnull, "r")
    log_fd = open(str(log_file), "a+", buffering=1)

    os.dup2(dev_null.fileno(), sys.stdin.fileno())
    os.dup2(log_fd.fileno(), sys.stdout.fileno())
    os.dup2(log_fd.fileno(), sys.stderr.fileno())

    # Write PID
    pid = os.getpid()
    pid_file.parent.mkdir(parents=True, exist_ok=True)
    pid_file.write_text(str(pid))


def get_running_daemon_pid() -> Optional[int]:
    """Return PID if daemon is running, else None."""
    if not PID_FILE.is_file():
        return None
    try:
        pid = int(PID_FILE.read_text().strip())
        # Check if process is alive
        os.kill(pid, 0)
        return pid
    except (ValueError, OSError):
        # Stale PID file
        try:
            PID_FILE.unlink()
        except OSError:
            pass
        return None


# ----------------------------------------------------------------------
# 6. CLI Command Handlers
# ----------------------------------------------------------------------

def cmd_start(args: argparse.Namespace) -> int:
    """Start the daemon in background or foreground."""
    existing_pid = get_running_daemon_pid()
    if existing_pid:
        print(f"[Daemon] Sashframe daemon is already running (PID: {existing_pid}).")
        return 0

    # 1. Verify installation
    setup_logging(to_console=True, log_file=LOG_FILE)
    logger.info("Starting Sashframe parent daemon pre-flight checks...")

    if not verify_installation(auto_install=not args.no_auto_install):
        logger.error("Pre-flight installation verification failed. Aborting start.")
        return 1

    # 2. Verify production build
    if not ensure_production_build(force_rebuild=args.rebuild):
        logger.error("Production build failed. Aborting start.")
        return 1

    # 3. Resolve any dev server port conflicts
    resolve_port_conflicts(args.port)

    # 4. Run foreground or daemonize
    if args.foreground:
        PID_FILE.parent.mkdir(parents=True, exist_ok=True)
        PID_FILE.write_text(str(os.getpid()))
        supervisor = DaemonSupervisor(host=args.host, port=args.port)
        supervisor.run()
        return 0
    else:
        print("[Daemon] Starting Sashframe daemon in background...")
        daemonize(PID_FILE, LOG_FILE)
        # We are now in daemon child process
        setup_logging(to_console=False, log_file=LOG_FILE)
        supervisor = DaemonSupervisor(host=args.host, port=args.port)
        supervisor.run()
        return 0


def cmd_stop(args: argparse.Namespace) -> int:
    """Stop the running daemon."""
    pid = get_running_daemon_pid()
    if not pid:
        print("[Daemon] No active daemon running.")
        return 0

    print(f"[Daemon] Stopping Sashframe daemon (PID: {pid})...")
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        print(f"[Daemon] Process {pid} not found. Cleaning up stale PID file.")
        if PID_FILE.is_file():
            PID_FILE.unlink()
        return 0
    except Exception as e:
        print(f"[Error] Failed to send SIGTERM to PID {pid}: {e}")
        return 1

    # Wait for termination
    for _ in range(50):
        try:
            os.kill(pid, 0)
            time.sleep(0.1)
        except OSError:
            break
    else:
        print(f"[Daemon] Daemon did not terminate in 5s; sending SIGKILL...")
        try:
            os.kill(pid, signal.SIGKILL)
        except OSError:
            pass

    if PID_FILE.is_file():
        try:
            PID_FILE.unlink()
        except OSError:
            pass

    print("[Daemon] Daemon stopped successfully.")
    return 0


def cmd_status(args: argparse.Namespace) -> int:
    """Report detailed daemon and subsystem status."""
    pid = get_running_daemon_pid()
    print("==========================================")
    print(" Sashframe - Production Daemon Status")
    print("==========================================")

    if pid:
        print(f" Status:        RUNNING ●")
        print(f" Daemon PID:    {pid}")
        print(f" URL:           http://localhost:4321")
        print(f" Log File:      {LOG_FILE}")
    else:
        print(" Status:        STOPPED ○")
        if PID_FILE.is_file():
            print(f" Warning:       Stale PID file detected at {PID_FILE}")

    # Subsystem inspection
    is_valid, missing = is_install_complete()
    print(f" Environment:   {'OK' if is_valid else 'Incomplete: ' + ', '.join(missing)}")
    print(f" Production:    {'Built (dist/index.html)' if DIST_INDEX.is_file() else 'Missing dist/'}")

    # Photos count (only count supported image files, ignoring hidden files like .gitkeep)
    supported_exts = {".jpg", ".jpeg", ".png", ".webp"}
    incoming_count = (
        len([p for p in INCOMING_DIR.iterdir() if p.is_file() and not p.name.startswith(".") and p.suffix.lower() in supported_exts])
        if INCOMING_DIR.exists()
        else 0
    )
    processed_count = len(list(PROCESSED_DIR.glob("*.webp"))) if PROCESSED_DIR.exists() else 0
    print(f" Photos:        {incoming_count} incoming, {processed_count} active processed")
    print("==========================================")
    return 0


def cmd_restart(args: argparse.Namespace) -> int:
    """Restart the daemon."""
    cmd_stop(args)
    time.sleep(1.0)
    return cmd_start(args)


def cmd_logs(args: argparse.Namespace) -> int:
    """Tail daemon log file."""
    if not LOG_FILE.is_file():
        print(f"[Daemon] No log file found at {LOG_FILE}.")
        return 1

    print(f"[Daemon] Streaming logs from {LOG_FILE} (Ctrl+C to exit)...")
    try:
        proc = subprocess.run(["tail", "-n", "50", "-f", str(LOG_FILE)])
        return proc.returncode
    except KeyboardInterrupt:
        return 0


# ----------------------------------------------------------------------
# Main CLI Entrypoint
# ----------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        prog="daemon.py",
        description="Sashframe Parent Production Daemon",
    )
    subparsers = parser.add_subparsers(dest="command", help="Daemon command")

    # Start command
    p_start = subparsers.add_parser("start", help="Start the daemon")
    p_start.add_argument("-f", "--foreground", action="store_true", help="Run in foreground")
    p_start.add_argument("-d", "--daemon", dest="foreground", action="store_false", help="Run as background daemon (default)")
    p_start.add_argument("--port", type=int, default=int(os.environ.get("PORT", "4321")), help="HTTP port (default: 4321)")
    p_start.add_argument("--host", type=str, default=os.environ.get("HOST", "0.0.0.0"), help="Host to bind (default: 0.0.0.0)")
    p_start.add_argument("--rebuild", action="store_true", help="Force rebuild of dist/ before starting")
    p_start.add_argument("--no-auto-install", action="store_true", help="Fail instead of running scripts/install.sh if missing")
    p_start.set_defaults(foreground=False)

    # Stop command
    subparsers.add_parser("stop", help="Stop the running daemon")

    # Status command
    subparsers.add_parser("status", help="Show daemon status")

    # Restart command
    p_restart = subparsers.add_parser("restart", help="Restart the daemon")
    p_restart.add_argument("-f", "--foreground", action="store_true", help="Run in foreground")
    p_restart.add_argument("-d", "--daemon", dest="foreground", action="store_false", help="Run as background daemon (default)")
    p_restart.add_argument("--port", type=int, default=int(os.environ.get("PORT", "4321")), help="HTTP port (default: 4321)")
    p_restart.add_argument("--host", type=str, default=os.environ.get("HOST", "0.0.0.0"), help="Host to bind (default: 0.0.0.0)")
    p_restart.add_argument("--rebuild", action="store_true", help="Force rebuild of dist/ before starting")
    p_restart.add_argument("--no-auto-install", action="store_true", help="Fail instead of running scripts/install.sh if missing")
    p_restart.set_defaults(foreground=False)

    # Logs command
    subparsers.add_parser("logs", help="Tail daemon logs")

    # If no arguments provided, default to starting in background
    if len(sys.argv) == 1:
        args = parser.parse_args(["start"])
    else:
        args = parser.parse_args()

    handlers = {
        "start": cmd_start,
        "stop": cmd_stop,
        "status": cmd_status,
        "restart": cmd_restart,
        "logs": cmd_logs,
    }

    handler = handlers.get(args.command)
    if handler:
        sys.exit(handler(args))
    else:
        parser.print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()
