import time
import pyautogui

print("Mova o mouse para cada alvo; Ctrl+C encerra.")
print("Play: posicione o mouse e aguarde a leitura abaixo.")
try:
    while True:
        x, y = pyautogui.position()
        print(f"\rPosição atual: [{x}, {y}]", end="", flush=True)
        time.sleep(0.2)
except KeyboardInterrupt:
    print()
