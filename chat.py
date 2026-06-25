import json
import urllib.request
import sys
import time
import threading

# --- CONFIGURACIÓN ---
OLLAMA_URL = "http://100.57.161.250:11434/api/generate"
MODEL = "qwen2.5:7b"

# --- COLORES ANSI ---
C_USER = "\033[96m"   # Cyan
C_BOT = "\033[92m"    # Verde
C_SYS = "\033[93m"    # Amarillo
C_RESET = "\033[0m"   # Reset

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
    # Limpiar la línea del spinner cuando termina
    sys.stdout.write('\r' + ' ' * 30 + '\r')
    sys.stdout.flush()

def typewriter(text):
    """Imprime el texto letra a letra para un efecto más natural."""
    for char in text:
        sys.stdout.write(char)
        sys.stdout.flush()
        time.sleep(0.01)
    print()

def main():
    global is_loading
    print(f"\n{C_SYS}=============================================={C_RESET}")
    print(f"{C_SYS}   🤖 CHAT DE TERMINAL IA ({MODEL}){C_RESET}")
    print(f"{C_SYS}=============================================={C_RESET}")
    print(f"{C_SYS}INFO: Escribe 'salir' para terminar.{C_RESET}\n")

    chat_context = []

    while True:
        try:
            # 1. Leer entrada del usuario
            user_input = input(f"{C_USER}Tú: {C_RESET}")
            
            if user_input.lower() in ['salir', 'exit', 'quit']:
                print(f"{C_SYS}¡Desconexión exitosa. Hasta pronto!{C_RESET}")
                break
            if not user_input.strip():
                continue

            # 2. Iniciar animación de carga
            is_loading = True
            t = threading.Thread(target=spinner)
            t.start()

            # 3. Preparar la petición HTTP (inyectando el contexto para que tenga memoria)
            payload = {
                "model": MODEL,
                "prompt": user_input,
                "stream": False,
                "context": chat_context
            }
            
            req = urllib.request.Request(
                OLLAMA_URL, 
                data=json.dumps(payload).encode('utf-8'), 
                headers={'Content-Type': 'application/json'}
            )

            # 4. Enviar petición y recibir respuesta
            try:
                response = urllib.request.urlopen(req)
                res_body = response.read()
                data = json.loads(res_body.decode('utf-8'))
                
                answer = data.get("response", "")
                # Guardar el contexto devuelto para la siguiente pregunta
                chat_context = data.get("context", [])
                
            except Exception as e:
                answer = f"Error de conexión con el servidor: {e}"

            # 5. Detener animación
            is_loading = False
            t.join()

            # 6. Imprimir respuesta con efecto
            sys.stdout.write(f"{C_BOT}Qwen: {C_RESET}")
            typewriter(answer)
            print() # Espacio extra para la siguiente pregunta

        except KeyboardInterrupt:
            # Capturar Ctrl+C para salir limpiamente
            is_loading = False
            print(f"\n{C_SYS}¡Desconexión forzada. Hasta pronto!{C_RESET}")
            break

if __name__ == "__main__":
    main()