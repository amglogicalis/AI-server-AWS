import subprocess
import json
import sys
import os

# --- COLORES Y ESTILOS ---
C_CYAN = "\033[96m"
C_GREEN = "\033[92m"
C_YELLOW = "\033[93m"
C_RED = "\033[91m"
C_BOLD = "\033[1m"
C_RESET = "\033[0m"

def load_env():
    env_vars = {}
    if os.path.exists('.env'):
        with open('.env', 'r') as f:
            for line in f:
                if '=' in line and not line.startswith('#'):
                    key, value = line.strip().split('=', 1)
                    env_vars[key.strip()] = value.strip()
    return env_vars

env = load_env()
PROFILE = env.get("AWS_PROFILE", "default")
REGION = env.get("AWS_DEFAULT_REGION", "us-east-1")

def run_aws(args):
    cmd = ["aws", "ec2"] + args + ["--profile", PROFILE, "--region", REGION, "--output", "json"]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        return json.loads(result.stdout)
    except subprocess.CalledProcessError as e:
        return None

def get_instances():
    data = run_aws(["describe-instances"])
    if not data: return []
    instances = []
    for res in data.get("Reservations", []):
        for inst in res.get("Instances", []):
            name = next((t['Value'] for t in inst.get("Tags", []) if t['Key'] == 'Name'), "Sin Nombre")
            instances.append({
                "id": inst.get("InstanceId"), 
                "name": name, 
                "state": inst.get("State", {}).get("Name")
            })
    return instances

def clear_screen():
    # Comando ANSI para limpiar la pantalla y volver al inicio
    sys.stdout.write("\033[2J\033[H")
    sys.stdout.flush()

def main():
    while True:
        clear_screen()
        instances = get_instances()
        
        print(f"{C_CYAN}{C_BOLD}=== GESTOR AWS | Perfil: {PROFILE} | Region: {REGION} ==={C_RESET}\n")
        print(f"{'#':<3} | {'ESTADO':<15} | {'NOMBRE':<20} | {'ID'}")
        print("-" * 60)
        
        for i, inst in enumerate(instances, 1):
            color = C_GREEN if inst['state'] == 'running' else (C_YELLOW if inst['state'] == 'stopped' else C_RED)
            print(f"{i:<3} | {color}{inst['state']:<15}{C_RESET} | {inst['name']:<20} | {inst['id']}")
        
        choice = input(f"\n{C_BOLD}Elige número (0 para salir): {C_RESET}")
        
        if choice == '0': 
            clear_screen()
            break
        
        try:
            idx = int(choice) - 1
            if 0 <= idx < len(instances):
                inst = instances[idx]
                print(f"\n{C_CYAN}Gestionando: {C_BOLD}{inst['name']}{C_RESET}")
                act = input("¿Acción? [1:Start, 2:Stop, 3:Terminate, 0:Atrás]: ")
                
                if act == '1': run_aws(["start-instances", "--instance-ids", inst['id']])
                elif act == '2': run_aws(["stop-instances", "--instance-ids", inst['id']])
                elif act == '3': 
                    if input(f"{C_RED}¿Confirmas destrucción total? (s/n): {C_RESET}") == 's': 
                        run_aws(["terminate-instances", "--instance-ids", inst['id']])
                
                print(f"\n{C_GREEN}Orden enviada. Refrescando lista...{C_RESET}")
                time.sleep(2) # Pausa breve para ver el mensaje antes de borrar
            else:
                input(f"{C_RED}Número inválido. Pulsa ENTER para continuar...{C_RESET}")
        except ValueError:
            input(f"{C_RED}Error. Pulsa ENTER para continuar...{C_RESET}")

if __name__ == "__main__":
    main()