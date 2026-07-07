#!/usr/bin/env python3
"""
check_models_s3.py — Data source externo para Terraform.

Comprueba si los modelos GGUF de la arquitectura CAP ya están
presentes en el bucket S3. Se ejecuta localmente (en la máquina
donde corre Terraform) durante terraform plan / terraform apply.

Entrada:  JSON por stdin con las claves:
          bucket, prefix_72b, prefix_32b, aws_profile, aws_region

Salida:   JSON por stdout con la clave:
          ready → "true"  si ambos prefijos tienen objetos en S3
          ready → "false" si falta alguno, el bucket no existe
                           o hay un error de autenticación

Requisitos:
  - Python 3.6+
  - aws CLI instalado y en el PATH
  - Credenciales válidas para el perfil especificado
"""
import json
import subprocess
import sys


def s3_prefix_has_objects(bucket: str, prefix: str, profile: str, region: str) -> bool:
    """
    Devuelve True si existe al menos un objeto bajo el prefijo S3 dado.
    En caso de error (bucket no existe, credenciales caducadas, etc.)
    devuelve False de forma silenciosa para no romper el plan de Terraform.
    """
    try:
        result = subprocess.run(
            [
                "aws", "s3", "ls",
                f"s3://{bucket}/{prefix}",
                "--profile", profile,
                "--region", region,
            ],
            capture_output=True,
            text=True,
            timeout=30,
        )
        # returncode 0 y salida no vacía → hay objetos bajo el prefijo
        return result.returncode == 0 and bool(result.stdout.strip())
    except FileNotFoundError:
        # aws CLI no instalado en la máquina local
        return False
    except subprocess.TimeoutExpired:
        return False
    except Exception:
        return False


def main() -> None:
    try:
        query = json.load(sys.stdin)
    except json.JSONDecodeError as exc:
        # Terraform external data source requiere siempre una respuesta JSON válida
        print(json.dumps({"ready": "false", "_error": str(exc)}))
        sys.exit(0)

    bucket     = query.get("bucket", "")
    prefix_72b = query.get("prefix_72b", "")
    prefix_32b = query.get("prefix_32b", "")
    profile    = query.get("aws_profile", "default")
    region     = query.get("aws_region", "us-east-1")

    # Ambos prefijos deben tener objetos para considerar los modelos listos
    has_72b = s3_prefix_has_objects(bucket, prefix_72b, profile, region)
    has_32b = s3_prefix_has_objects(bucket, prefix_32b, profile, region)

    ready = has_72b and has_32b
    print(json.dumps({"ready": "true" if ready else "false"}))


if __name__ == "__main__":
    main()
