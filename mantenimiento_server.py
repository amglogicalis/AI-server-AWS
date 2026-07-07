import subprocess
import json
import sys
import os
import time

# Habilitar colores ANSI en Windows
if os.name == 'nt':
    os.system('')

# --- COLORES ---
C_CYAN    = "\033[96m"
C_GREEN   = "\033[92m"
C_YELLOW  = "\033[93m"
C_RED     = "\033[91m"
C_BOLD    = "\033[1m"
C_RESET   = "\033[0m"

# --- UTF-8 en Windows ---
if os.name == 'nt':
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    sys.stderr.reconfigure(encoding='utf-8', errors='replace')

def load_tf_vars():
    tf_vars = {}
    if os.path.exists('terraform.tfvars'):
        with open('terraform.tfvars', 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    key, val = line.split('=', 1)
                    val = val.strip().strip('"').strip("'")
                    tf_vars[key.strip()] = val
    return tf_vars

def load_env(env_file=".env"):
    env = {}
    if os.path.exists(env_file):
        with open(env_file, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    key, value = line.split("=", 1)
                    env[key.strip()] = value.strip()
    return env

tf_vars = load_tf_vars()
env     = load_env()

PROFILE = tf_vars.get("aws_profile") or env.get("AWS_PROFILE") or "personal"
REGION  = tf_vars.get("aws_region") or env.get("AWS_DEFAULT_REGION") or "eu-central-1"

def run_aws(args):
    cmd = ["aws", "ec2"] + args + ["--profile", PROFILE, "--region", REGION, "--output", "json"]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, encoding='utf-8', check=True)
        return json.loads(result.stdout)
    except subprocess.CalledProcessError as e:
        print(f"{C_RED}Error AWS: {e.stderr}{C_RESET}")
        return None

def get_instances():
    data = run_aws(["describe-instances"])
    if not data:
        return []
    instances = []
    for res in data.get("Reservations", []):
        for inst in res.get("Instances", []):
            state = inst.get("State", {}).get("Name", "?")
            if state == "terminated":
                continue  # No mostrar instancias terminadas
            name = next(
                (t['Value'] for t in inst.get("Tags", []) if t['Key'] == 'Name'),
                "Sin Nombre"
            )
            public_ip = inst.get("PublicIpAddress", "-")
            instances.append({
                "id":       inst.get("InstanceId"),
                "name":     name,
                "state":    state,
                "type":     inst.get("InstanceType", "?"),
                "ip":       public_ip,
            })
    return instances

def state_color(state):
    return {
        "running":  C_GREEN,
        "stopped":  C_YELLOW,
        "stopping": C_YELLOW,
        "pending":  C_CYAN,
    }.get(state, C_RED)

def clear_screen():
    sys.stdout.write("\033[2J\033[H")
    sys.stdout.flush()

def print_header():
    print(f"{C_CYAN}{C_BOLD}{'='*65}")
    print(f"  GESTOR AWS  |  Perfil: {PROFILE}  |  Region: {REGION}")
    print(f"{'='*65}{C_RESET}\n")

def main():
    while True:
        clear_screen()
        instances = get_instances()

        print_header()

        if not instances:
            print(f"{C_YELLOW}  No hay instancias activas en {REGION}.{C_RESET}\n")
        else:
            print(f"  {'#':<3}  {'TIPO':<14}  {'ESTADO':<12}  {'IP':<18}  NOMBRE")
            print(f"  {'-'*60}")
            for i, inst in enumerate(instances, 1):
                col = state_color(inst['state'])
                print(
                    f"  {i:<3}  {inst['type']:<14}  "
                    f"{col}{inst['state']:<12}{C_RESET}  "
                    f"{inst['ip']:<18}  {inst['name']}"
                )

        print(f"\n{C_BOLD}Elige numero de instancia  (0 para salir): {C_RESET}", end="")
        choice = input().strip()

        if choice == '0':
            clear_screen()
            print(f"{C_GREEN}Adios.{C_RESET}\n")
            break

        try:
            idx = int(choice) - 1
            if not (0 <= idx < len(instances)):
                input(f"{C_RED}Numero invalido. Pulsa ENTER...{C_RESET}")
                continue

            inst = instances[idx]
            clear_screen()
            print_header()
            print(f"  Instancia : {C_BOLD}{inst['name']}{C_RESET}  ({inst['id']})")
            print(f"  Estado    : {state_color(inst['state'])}{inst['state']}{C_RESET}")
            print(f"  IP publica: {inst['ip']}\n")
            print(f"  {C_BOLD}Acciones:{C_RESET}")
            print(f"    1) Start       - Encender la instancia")
            print(f"    2) Stop        - Apagar (los datos se conservan)")
            print(f"    3) Terminate   - {C_RED}DESTRUIR definitivamente{C_RESET}")
            print(f"    0) Atras\n")
            print(f"{C_BOLD}Accion: {C_RESET}", end="")
            act = input().strip()

            if act == '0':
                continue
            elif act == '1':
                run_aws(["start-instances", "--instance-ids", inst['id']])
                print(f"\n{C_GREEN}  Orden START enviada. La instancia tardara ~30s en estar disponible.{C_RESET}")
            elif act == '2':
                run_aws(["stop-instances", "--instance-ids", inst['id']])
                print(f"\n{C_YELLOW}  Orden STOP enviada. La GPU dejara de cobrar en ~1 min.{C_RESET}")
            elif act == '3':
                print(f"\n{C_RED}{C_BOLD}  ATENCION: Esto destruye la instancia y sus datos locales.{C_RESET}")
                print(f"{C_RED}  Los modelos del S3 quedan intactos.{C_RESET}")
                print(f"{C_BOLD}  Confirma con 's' para continuar: {C_RESET}", end="")
                confirm = input().strip().lower()
                if confirm == 's':
                    run_aws(["terminate-instances", "--instance-ids", inst['id']])
                    print(f"\n{C_RED}  Orden TERMINATE enviada.{C_RESET}")
                else:
                    print(f"\n{C_GREEN}  Cancelado.{C_RESET}")
            else:
                print(f"{C_RED}  Opcion no valida.{C_RESET}")

            time.sleep(2)

        except ValueError:
            input(f"{C_RED}Entrada no valida. Pulsa ENTER...{C_RESET}")

if __name__ == "__main__":
    main()