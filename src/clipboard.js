import { execFileSync } from "node:child_process";

export function readClipboard() {
  if (process.platform === "win32") {
    return execFileSync("powershell.exe", ["-NoProfile", "-Command", "Get-Clipboard -Raw"], {
      encoding: "utf8",
      windowsHide: true
    }).trim();
  }

  if (process.platform === "darwin") {
    return execFileSync("pbpaste", { encoding: "utf8" }).trim();
  }

  for (const command of [
    ["wl-paste", []],
    ["xclip", ["-selection", "clipboard", "-o"]],
    ["xsel", ["--clipboard", "--output"]]
  ]) {
    try {
      return execFileSync(command[0], command[1], { encoding: "utf8" }).trim();
    } catch {
      // Try next clipboard command.
    }
  }

  throw new Error("Clipboard is not available on this platform.");
}

export function writeClipboard(text) {
  if (process.platform === "win32") {
    execFileSync("powershell.exe", ["-NoProfile", "-Command", "$input | Set-Clipboard"], {
      input: text,
      encoding: "utf8",
      windowsHide: true
    });
    return;
  }

  if (process.platform === "darwin") {
    execFileSync("pbcopy", { input: text, encoding: "utf8" });
    return;
  }

  for (const command of [
    ["wl-copy", []],
    ["xclip", ["-selection", "clipboard"]],
    ["xsel", ["--clipboard", "--input"]]
  ]) {
    try {
      execFileSync(command[0], command[1], { input: text, encoding: "utf8" });
      return;
    } catch {
      // Try next clipboard command.
    }
  }

  throw new Error("Clipboard is not available on this platform.");
}
