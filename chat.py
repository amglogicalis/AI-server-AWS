import json
import urllib.request
import urllib.error
import sys
import time
import threading
import os

# --- CONFIGURACIÓN (cargada dinámicamente desde .env) ---
def load_env(env_file: str = ".env") -> dict:
    """Lee el archivo .env del directorio del script y devuelve un dict clave=valor."""
    env = {}
    env_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), env_file)
    if os.path.exists(env_path):
        with open(env_path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    key, value = line.split("=", 1)
                    env[key.strip()] = value.strip()
    return env

env = load_env()
OLLAMA_URL = env.get("OLLAMA_URL", "http://localhost:11434/api/generate")
DEFAULT_MODEL = env.get("MODEL_NAME", "qwen-coder-32b")

# Extraer URL base para listar modelos (/api/tags)
base_url = OLLAMA_URL.replace("/api/generate", "")
if base_url.endswith("/"):
    base_url = base_url[:-1]
TAGS_URL = f"{base_url}/api/tags"

# --- COLORES ANSI ---
C_USER    = "\033[96m"   # Cyan
C_BOT     = "\033[92m"   # Verde
C_SYS     = "\033[93m"   # Amarillo
C_ALERT   = "\033[91m"   # Rojo
C_HIGHLIGHT = "\033[95m" # Magenta/Rosa
C_RESET   = "\033[0m"    # Reset

is_loading = False

def spinner():
    """Muestra una animación de carga en la terminal mientras espera la respuesta."""
    chars = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏']
    i = 0
    while is_loading:
        sys.stdout.write(f'\r{C_SYS}Pensando {chars[i % len(chars)]}{C_RESET}')
        sys.stdout.flush()
        time.sleep(0.1)
        i += 1
    sys.stdout.write('\r' + ' ' * 30 + '\r')
    sys.stdout.flush()

def typewriter(text: str):
    """Imprime el texto con un ligero retardo simulando máquina de escribir."""
    for char in text:
        sys.stdout.write(char)
        sys.stdout.flush()
        time.sleep(0.005)
    print()

def get_available_models():
    """Consulta la API de Ollama y devuelve la lista de modelos registrados."""
    try:
        req = urllib.request.Request(TAGS_URL)
        with urllib.request.urlopen(req, timeout=5) as response:
            data = json.loads(response.read().decode("utf-8"))
            return [m.get("name") for m in data.get("models", [])]
    except Exception:
        return []

def select_model_menu(models):
    """Muestra un menú de selección de modelo y devuelve el seleccionado."""
    print(f"\n{C_HIGHLIGHT}=== SELECCIÓN DE MODELO ==={C_RESET}")
    for idx, m in enumerate(models, 1):
        # Etiquetas informativas de rendimiento estimado
        info = ""
        if "32b" in m.lower():
            info = f" {C_BOT}[Recomendado - 100% GPU / Súper Rápido]{C_RESET}"
        elif "72b" in m.lower():
            info = f" {C_SYS}[CPU+GPU Offload / Más lento]{C_RESET}"
        
        print(f" {C_HIGHLIGHT}{idx}){C_RESET} {m}{info}")
    
    while True:
        try:
            choice = input(f"\nSelecciona un número (1-{len(models)}) o presiona Enter para usar por defecto: ").strip()
            if not choice:
                return DEFAULT_MODEL
            idx = int(choice) - 1
            if 0 <= idx < len(models):
                return models[idx]
            else:
                print(f"{C_ALERT}Número fuera de rango.{C_RESET}")
        except ValueError:
            print(f"{C_ALERT}Entrada no válida. Introduce un número.{C_RESET}")

def main():
    global is_loading
    
    # 1. Obtener modelos del servidor
    print(f"{C_SYS}Conectando al servidor Ollama en {base_url}...{C_RESET}")
    models = get_available_models()
    
    selected_model = DEFAULT_MODEL
    if models:
        # Si el modelo por defecto está en la lista, presentarlo primero.
        # De lo contrario, dejar que el usuario elija o autodetectar
        selected_model = select_model_menu(models)
    else:
        print(f"{C_ALERT}Advertencia: No se pudo conectar u obtener modelos de {TAGS_URL}.{C_RESET}")
        print(f"Usando modelo por defecto configurado: {selected_model}")
    
    print(f"\n{C_SYS}=============================================={C_RESET}")
    print(f"{C_SYS}   🤖 CHAT DE TERMINAL IA{C_RESET}")
    print(f"   {C_SYS}Modelo activo : {C_HIGHLIGHT}{selected_model}{C_RESET}")
    print(f"   {C_SYS}Endpoint API  : {OLLAMA_URL}{C_RESET}")
    print(f"{C_SYS}=============================================={C_RESET}")
    print(f"{C_SYS}COMANDOS DISPONIBLES:{C_RESET}")
    print(f"  {C_HIGHLIGHT}/model{C_RESET}   - Cambiar de modelo en caliente")
    print(f"  {C_HIGHLIGHT}/clear{C_RESET}   - Limpiar historial de conversación")
    print(f"  {C_HIGHLIGHT}/salir{C_RESET}   - Salir del chat")
    print(f"{C_SYS}=============================================={C_RESET}\n")

    chat_context = []

    while True:
        try:
            user_input = input(f"{C_USER}Tú: {C_RESET}").strip()

            if not user_input:
                continue

            # --- CONTROL DE COMANDOS DEL CHAT ---
            if user_input.lower() == '/salir':
                print(f"\n{C_SYS}¡Desconexión exitosa. Hasta pronto!{C_RESET}")
                break

            elif user_input.lower() == '/clear':
                chat_context = []
                print(f"\n{C_SYS}🧹 Historial de conversación y memoria limpiados.{C_RESET}\n")
                continue

            elif user_input.lower() == '/model':
                models = get_available_models()
                if models:
                    new_model = select_model_menu(models)
                    if new_model != selected_model:
                        selected_model = new_model
                        chat_context = [] # Limpiar contexto para evitar errores de tokenizador entre modelos
                        print(f"\n{C_HIGHLIGHT}✓ Modelo cambiado a: {selected_model}{C_RESET}")
                        print(f"{C_SYS}🧹 Memoria del chat reiniciada para el nuevo modelo.{C_RESET}\n")
                    else:
                        print(f"\n{C_SYS}Permaneces en el modelo: {selected_model}{C_RESET}\n")
                else:
                    print(f"\n{C_ALERT}Error: No se pudo comunicar con el servidor para listar modelos.{C_RESET}\n")
                continue
            
            # Evitar comandos mal escritos o slash no soportados
            if user_input.startswith('/'):
                print(f"{C_ALERT}Comando no reconocido. Prueba con /model, /clear o /salir.{C_RESET}")
                continue

            # --- PROCESAR MENSAJE ---
            is_loading = True
            t = threading.Thread(target=spinner, daemon=True)
            t.start()

            payload = {
                "model": selected_model,
                "prompt": user_input,
                "stream": False,
                "context": chat_context,
            }

            req = urllib.request.Request(
                OLLAMA_URL,
                data=json.dumps(payload).encode("utf-8"),
                headers={"Content-Type": "application/json"},
            )

            try:
                response = urllib.request.urlopen(req, timeout=120)
                res_body = response.read()
                data = json.loads(res_body.decode("utf-8"))

                answer = data.get("response", "")
                chat_context = data.get("context", [])

            except urllib.error.URLError as e:
                answer = f"Error de conexión con el servidor Ollama: {e.reason}"
            except Exception as e:
                answer = f"Error inesperado: {e}"

            is_loading = False
            t.join(timeout=1)

            # Imprimir respuesta
            model_display = selected_model.split(":")[0]
            sys.stdout.write(f"{C_BOT}{model_display}: {C_RESET}")
            typewriter(answer)
            print()

        except KeyboardInterrupt:
            is_loading = False
            print(f"\n\n{C_SYS}¡Desconexión forzada. Hasta pronto!{C_RESET}")
            break

if __name__ == "__main__":
    # Habilitar soporte de colores ANSI en Windows cmd/powershell
    if os.name == 'nt':
        os.system('')
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
        sys.stderr.reconfigure(encoding='utf-8', errors='replace')
    main()