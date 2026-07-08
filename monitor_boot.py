import time
import json
import subprocess
import sys
import re

INSTANCE_ID = "i-0a7848070791694c9"
REGION = "eu-central-1"
PROFILE = "personal"
KEY_FILE = "vockey.pem"

def run_cmd(cmd):
    try:
        res = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        return res.returncode, res.stdout.strip(), res.stderr.strip()
    except Exception as e:
        return -1, "", str(e)

def print_progress_bar(percentage, extra_info=""):
    bar_length = 30
    filled_length = int(round(bar_length * percentage / 100))
    bar = '█' * filled_length + '░' * (bar_length - filled_length)
    sys.stdout.write(f"\r[{bar}] {percentage:.1f}% | {extra_info:<45}")
    sys.stdout.flush()

def main():
    print("==================================================")
    print("🚀 INICIANDO Y MONITOREANDO SERVIDOR GPU OLLAMA")
    print("==================================================")

    # 1. Start EC2 instance
    print("--> Solicitando encendido de la instancia en AWS...")
    cmd_start = f"aws ec2 start-instances --instance-ids {INSTANCE_ID} --region {REGION} --profile {PROFILE}"
    code, out, err = run_cmd(cmd_start)
    if code != 0:
        print(f"❌ Error al iniciar la instancia: {err}")
        sys.exit(1)

    # 2. Wait for instance to be running
    ip = None
    print("--> Esperando a que el estado sea 'running'...", end="", flush=True)
    while True:
        cmd_desc = f"aws ec2 describe-instances --instance-ids {INSTANCE_ID} --region {REGION} --profile {PROFILE}"
        code, out, err = run_cmd(cmd_desc)
        if code == 0:
            try:
                data = json.loads(out)
                inst = data['Reservations'][0]['Instances'][0]
                state = inst['State']['Name']
                if state == 'running':
                    ip = inst.get('PublicIpAddress')
                    break
            except Exception:
                pass
        print(".", end="", flush=True)
        time.sleep(4)
    print(f"\n✅ Instancia activa! IP Pública: {ip}")

    # 3. Wait for SSH to be responsive
    print("--> Esperando respuesta de red y servicio SSH...", end="", flush=True)
    ssh_test_cmd = f'ssh -i {KEY_FILE} -o StrictHostKeyChecking=no -o ConnectTimeout=5 ubuntu@{ip} "echo ok"'
    while True:
        code, out, err = run_cmd(ssh_test_cmd)
        if code == 0 and out == "ok":
            break
        print(".", end="", flush=True)
        time.sleep(3)
    print("\n✅ Conexión SSH establecida.")

    # 4. Monitor Restore Log
    print("--> Monitoreando sincronización de modelos desde S3...")
    restore_log_cmd = f'ssh -i {KEY_FILE} -o StrictHostKeyChecking=no ubuntu@{ip} "tail -n 3 /var/log/ollama-nvme-restore.log 2>/dev/null"'
    
    last_val = 0
    while True:
        code, out, err = run_cmd(restore_log_cmd)
        if code != 0 or not out:
            print_progress_bar(0, "Iniciando servicio de restauración...")
            time.sleep(3)
            continue
        
        # Check if restore completed
        if "=== [RESTORE END]" in out or "Iniciando servicio Ollama..." in out:
            print_progress_bar(100.0, "Ollama listo y modelos sincronizados!")
            print()
            break
        
        # Parse progress: e.g. "Completed 11.9 GiB/62.6 GiB"
        match = re.findall(r"Completed\s+([\d\.]+)\s+GiB/([\d\.]+)\s+GiB", out)
        if match:
            current, total = float(match[-1][0]), float(match[-1][1])
            pct = (current / total) * 100
            print_progress_bar(pct, f"Sincronizando: {current:.1f}/{total:.1f} GB")
        else:
            print_progress_bar(last_val, "Preparando sincronización...")
        time.sleep(3)

    # 5. Output Aider command
    print("\n" + "=" * 50)
    print("🎉 SERVIDOR OLLAMA TOTALMENTE CONFIGURADO Y ACTIVO")
    print("=" * 50)
    print(f"IP Servidor : {ip}")
    print(f"API Base    : http://{ip}:11434/v1")
    print(f"Modelos     : qwen2.5-coder:32b, qwen2.5:72b")
    print("-" * 50)
    print("👉 COMANDO PARA INICIAR AIDER:")
    print(f"aider --model ollama/qwen2.5-coder:32b --openai-api-base http://{ip}:11434/v1")
    print("=" * 50)

if __name__ == "__main__":
    main()
