from __future__ import annotations

import json
import re
import threading
import time
from pathlib import Path

import pyautogui
import pytesseract
from PIL import ImageOps
from windows_toasts import Toast, WindowsToaster

BASE_DIR = Path(__file__).resolve().parent
CONFIG_PATH = BASE_DIR / "config.json"
STOP = threading.Event()
PAUSED = threading.Event()


def load_config() -> dict:
    if not CONFIG_PATH.exists():
        raise SystemExit("Crie config.json a partir de config.example.json e preencha as regiões da tela.")
    with CONFIG_PATH.open(encoding="utf-8") as file:
        config = json.load(file)
    for key in ("play_point", "level_region", "captcha_region"):
        if key not in config:
            raise SystemExit(f"Configuração ausente: {key}")
    return config


def screenshot_text(region: list[int]) -> str:
    image = pyautogui.screenshot(region=tuple(region))
    image = ImageOps.grayscale(image)
    image = ImageOps.autocontrast(image)
    return pytesseract.image_to_string(image, config="--psm 6").lower()


def read_level(region: list[int]) -> int | None:
    text = screenshot_text(region)
    numbers = re.findall(r"\d+", text.replace("o", "0").replace("i", "1"))
    return max((int(value) for value in numbers), default=None)


def captcha_visible(config: dict) -> bool:
    text = screenshot_text(config["captcha_region"])
    return any(keyword.lower() in text for keyword in config.get("captcha_keywords", []))


def notify_captcha() -> None:
    toaster = WindowsToaster("RPA mudinhoX")
    toast = Toast()
    toast.text_fields = ["Captcha necessário", "Preencha o captcha no mudinhoX para continuar."]
    toaster.show_toast(toast)


def keyboard_controls() -> None:
    while not STOP.is_set():
        if pyautogui.is_pressed("f9"):
            STOP.set()
            return
        if pyautogui.is_pressed("f8"):
            if PAUSED.is_set():
                PAUSED.clear()
                print("Retomado.")
            else:
                PAUSED.set()
                print("Pausado.")
            time.sleep(0.5)
        time.sleep(0.05)


def wait(seconds: float) -> None:
    end = time.monotonic() + seconds
    while time.monotonic() < end and not STOP.is_set():
        while PAUSED.is_set() and not STOP.is_set():
            time.sleep(0.1)
        time.sleep(0.05)


def send_chat(command: str, delay: float) -> None:
    pyautogui.press("enter")
    wait(delay)
    pyautogui.write(command, interval=0.03)
    pyautogui.press("enter")
    wait(delay)


def main() -> None:
    config = load_config()
    pyautogui.FAILSAFE = True
    threading.Thread(target=keyboard_controls, daemon=True).start()
    print("Começando em 5 segundos. F8 pausa/retoma; F9 encerra; mover o mouse ao canto superior esquerdo também encerra.")
    wait(5)
    delay = float(config.get("key_delay_seconds", 0.15))
    poll_seconds = float(config.get("poll_seconds", 2))
    target = int(config.get("level_target", 350))

    try:
        while not STOP.is_set():
            send_chat("/icarus", delay)
            pyautogui.click(*config["play_point"])
            print("Play acionado; aguardando nível", target)
            while not STOP.is_set():
                if captcha_visible(config):
                    notify_captcha()
                    print("Captcha detectado; aguardando preenchimento manual.")
                    while captcha_visible(config) and not STOP.is_set():
                        wait(1)
                    print("Captcha liberado.")
                level = read_level(config["level_region"])
                if level is not None:
                    print(f"Nível detectado: {level}")
                if level == target:
                    break
                wait(poll_seconds)
            if STOP.is_set():
                break
            send_chat("/resetar", delay)
            wait(poll_seconds)
    except pyautogui.FailSafeException:
        print("Execução encerrada pelo fail-safe do PyAutoGUI.")
    finally:
        STOP.set()
        print("RPA encerrado.")


if __name__ == "__main__":
    main()
