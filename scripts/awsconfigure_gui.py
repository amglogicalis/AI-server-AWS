#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# awsconfigure_gui.py - WSL/Linux graphical interface for AWS Credentials Manager

import os
import sys
import json
import shutil
import subprocess
import tkinter as tk
from tkinter import ttk, messagebox

# Colors - Catppuccin-inspired modern dark theme
BG_COLOR = "#1e1e2e"          # Main background
CARD_BG = "#252538"           # Inputs and headers frame bg
TEXT_COLOR = "#cdd6f4"        # Main text
ACCENT_BLUE = "#89b4fa"       # Primary accent blue
ACCENT_GREEN = "#a6e3a1"      # Success green
ACCENT_RED = "#f38ba8"        # Warning/Delete red
TEXT_MUTED = "#7f849c"        # Muted labels
INPUT_BG = "#313244"          # Input background
INPUT_BORDER = "#45475a"      # Input border

CRED_PATH = os.path.expanduser("~/.aws/credentials")

# Ensure AWS directory exists
os.makedirs(os.path.dirname(CRED_PATH), exist_ok=True)
if not os.path.exists(CRED_PATH):
    open(CRED_PATH, 'a').close()

# -------------------------------------------------------
# DATA ACCESS FUNCTIONS
# -------------------------------------------------------
def read_profiles():
    if not os.path.exists(CRED_PATH):
        return []
    profiles = []
    try:
        with open(CRED_PATH, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line.startswith("[") and line.endswith("]"):
                    profile = line[1:-1].strip()
                    if profile not in profiles:
                        profiles.append(profile)
    except Exception as e:
        print(f"Error reading credentials file: {e}", file=sys.stderr)
    return profiles

def get_profile_data(profile_name):
    if not os.path.exists(CRED_PATH):
        return {}
    data = {}
    inside = False
    try:
        with open(CRED_PATH, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line.startswith("[") and line.endswith("]"):
                    current_profile = line[1:-1].strip()
                    if current_profile == profile_name:
                        inside = True
                    else:
                        inside = False
                    continue
                if inside and "=" in line:
                    key, val = line.split("=", 1)
                    data[key.strip()] = val.strip()
    except Exception as e:
        print(f"Error reading profile data: {e}", file=sys.stderr)
    return data

def save_profile_data(profile, ak, sk, token=""):
    lines = []
    if os.path.exists(CRED_PATH):
        try:
            with open(CRED_PATH, "r", encoding="utf-8") as f:
                lines = f.readlines()
        except Exception as e:
            print(f"Error reading file before save: {e}", file=sys.stderr)
            
    result = []
    inside_target = False
    found_profile = False
    keys_handled = {"ak": False, "sk": False, "token": False}
    add_token = bool(token and token.strip())

    for line in lines:
        trimmed = line.strip()
        if trimmed.startswith("[") and trimmed.endswith("]"):
            cur = trimmed[1:-1].strip()
            if inside_target:
                # Add missing keys to the end of the target profile section
                if not keys_handled["ak"]:
                    result.append(f"aws_access_key_id = {ak}\n")
                if not keys_handled["sk"]:
                    result.append(f"aws_secret_access_key = {sk}\n")
                if not keys_handled["token"] and add_token:
                    result.append(f"aws_session_token = {token}\n")
                inside_target = False
            if cur == profile:
                inside_target = True
                found_profile = True
                result.append(line)
                continue

        if inside_target:
            if trimmed.startswith("aws_access_key_id"):
                result.append(f"aws_access_key_id = {ak}\n")
                keys_handled["ak"] = True
            elif trimmed.startswith("aws_secret_access_key"):
                result.append(f"aws_secret_access_key = {sk}\n")
                keys_handled["sk"] = True
            elif trimmed.startswith("aws_session_token"):
                if add_token:
                    result.append(f"aws_session_token = {token}\n")
                keys_handled["token"] = True
            else:
                result.append(line)
        else:
            result.append(line)

    # If the file ended while we were inside the target profile
    if inside_target:
        if not keys_handled["ak"]:
            result.append(f"aws_access_key_id = {ak}\n")
        if not keys_handled["sk"]:
            result.append(f"aws_secret_access_key = {sk}\n")
        if not keys_handled["token"] and add_token:
            result.append(f"aws_session_token = {token}\n")

    # If the profile was not found, append it
    if not found_profile:
        if result and result[-1].strip() != "":
            result.append("\n")
        result.append(f"[{profile}]\n")
        result.append(f"aws_access_key_id = {ak}\n")
        result.append(f"aws_secret_access_key = {sk}\n")
        if add_token:
            result.append(f"aws_session_token = {token}\n")

    try:
        with open(CRED_PATH, "w", encoding="utf-8") as f:
            f.writelines(result)
        os.chmod(CRED_PATH, 0o600)
    except Exception as e:
        messagebox.showerror("Error de Escritura", f"No se pudo escribir en el archivo:\n{e}")

def remove_profile_data(profile):
    if not os.path.exists(CRED_PATH):
        return
    try:
        with open(CRED_PATH, "r", encoding="utf-8") as f:
            lines = f.readlines()
    except Exception as e:
        print(f"Error reading file before removal: {e}", file=sys.stderr)
        return
        
    result = []
    inside_target = False
    for line in lines:
        trimmed = line.strip()
        if trimmed.startswith("[") and trimmed.endswith("]"):
            cur = trimmed[1:-1].strip()
            inside_target = (cur == profile)
            if inside_target:
                continue
        if inside_target:
            continue
        result.append(line)

    # Clean double newlines at the end
    while len(result) > 1 and result[-1].strip() == "" and result[-2].strip() == "":
        result.pop()

    try:
        with open(CRED_PATH, "w", encoding="utf-8") as f:
            f.writelines(result)
        os.chmod(CRED_PATH, 0o600)
    except Exception as e:
        messagebox.showerror("Error de Escritura", f"No se pudo guardar la eliminación:\n{e}")

# -------------------------------------------------------
# VALIDATION IMPLEMENTATION
# -------------------------------------------------------
def validate_credentials_cli(profile):
    if not shutil.which("aws"):
        return False, "El comando 'aws' no se encontró en el PATH.\nInstala AWS CLI y asegúrate de que esté en el PATH."
    
    try:
        proc = subprocess.run(
            ["aws", "sts", "get-caller-identity", "--profile", profile],
            capture_output=True,
            text=True
        )
        if proc.returncode == 0:
            try:
                j = json.loads(proc.stdout)
                msg = f"CREDENCIALES VÁLIDAS\n\nAccount : {j.get('Account')}\nUserId  : {j.get('UserId')}\nArn     : {j.get('Arn')}"
            except Exception:
                msg = f"CREDENCIALES VÁLIDAS\n\n{proc.stdout}"
            return True, msg
        else:
            err = proc.stderr.strip() or proc.stdout.strip()
            return False, f"CREDENCIALES INVÁLIDAS o EXPIRADAS.\n\n{err}"
    except Exception as e:
        return False, f"Error inesperado al ejecutar AWS CLI.\n\n{str(e)}"

# -------------------------------------------------------
# USER INTERACTION / EVENT HANDLERS
# -------------------------------------------------------
class AwsConfigureGuiApp:
    def __init__(self, root):
        self.root = root
        self.root.title("AWS Credentials Manager (WSL)")
        self.root.geometry("660x650")
        self.root.resizable(False, False)
        self.root.configure(bg=BG_COLOR)
        
        # Apply TTK Styles for Combobox dropdown
        self.style = ttk.Style()
        self.style.theme_use('clam')
        self.style.configure('TCombobox', 
                             fieldbackground=INPUT_BG, 
                             background=INPUT_BORDER, 
                             foreground=TEXT_COLOR)
        self.style.map('TCombobox', 
                       fieldbackground=[('readonly', INPUT_BG)], 
                       foreground=[('readonly', TEXT_COLOR)])

        self.setup_ui()
        self.refresh_combo_profiles()
        
    def setup_ui(self):
        # 1. Header Blue Accent Bar
        top_bar = tk.Frame(self.root, bg=ACCENT_BLUE, height=8)
        top_bar.pack(fill=tk.X, side=tk.TOP)
        
        main_frame = tk.Frame(self.root, bg=BG_COLOR, padx=25, pady=20)
        main_frame.pack(fill=tk.BOTH, expand=True)

        # 2. Existing Profile Frame
        row1 = tk.Frame(main_frame, bg=BG_COLOR)
        row1.pack(fill=tk.X, pady=(0, 15))
        
        lbl_combo = tk.Label(row1, text="Perfil existente:", font=("Segoe UI", 10, "bold"), fg=TEXT_COLOR, bg=BG_COLOR)
        lbl_combo.pack(side=tk.LEFT)
        
        self.combo_profile = ttk.Combobox(row1, font=("Segoe UI", 10), state="readonly")
        self.combo_profile.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=(15, 0))
        self.combo_profile.bind("<<ComboboxSelected>>", self.on_profile_selected)

        # Separator 1
        sep1 = tk.Frame(main_frame, bg=INPUT_BORDER, height=1)
        sep1.pack(fill=tk.X, pady=(0, 15))

        # 3. Profile Name Fields
        lbl_profile = tk.Label(main_frame, text="Nombre del perfil:", font=("Segoe UI", 10, "bold"), fg=TEXT_COLOR, bg=BG_COLOR)
        lbl_profile.pack(anchor=tk.W, pady=(0, 5))
        
        row_profile = tk.Frame(main_frame, bg=BG_COLOR)
        row_profile.pack(fill=tk.X, pady=(0, 15))
        
        self.entry_profile = self.create_modern_entry(row_profile)
        self.entry_profile.pack(side=tk.LEFT, fill=tk.X, expand=True)
        self.entry_profile.focus_set()
        
        btn_nuevo = self.create_flat_button(row_profile, "Nuevo", self.on_btn_nuevo, "#45475a", "#585b70", width=10)
        btn_nuevo.pack(side=tk.LEFT, padx=(10, 0))
        
        btn_eliminar = self.create_flat_button(row_profile, "Eliminar", self.on_btn_eliminar, ACCENT_RED, "#e06c75", width=10)
        btn_eliminar.pack(side=tk.LEFT, padx=(10, 0))

        # Separator 2
        sep2 = tk.Frame(main_frame, bg=INPUT_BORDER, height=1)
        sep2.pack(fill=tk.X, pady=(0, 15))

        # 4. Access Key ID
        lbl_ak = tk.Label(main_frame, text="Access Key ID:", font=("Segoe UI", 10, "bold"), fg=TEXT_COLOR, bg=BG_COLOR)
        lbl_ak.pack(anchor=tk.W, pady=(0, 5))
        self.entry_ak = self.create_modern_entry(main_frame)
        self.entry_ak.pack(fill=tk.X, pady=(0, 15))
        
        # 5. Secret Access Key
        lbl_sk = tk.Label(main_frame, text="Secret Access Key:", font=("Segoe UI", 10, "bold"), fg=TEXT_COLOR, bg=BG_COLOR)
        lbl_sk.pack(anchor=tk.W, pady=(0, 5))
        
        row_sk = tk.Frame(main_frame, bg=BG_COLOR)
        row_sk.pack(fill=tk.X, pady=(0, 15))
        
        self.entry_sk = self.create_modern_entry(row_sk, show="•")
        self.entry_sk.pack(side=tk.LEFT, fill=tk.X, expand=True)
        
        self.btn_show_sk = self.create_flat_button(row_sk, "Ver", self.toggle_sk_visibility, "#45475a", "#585b70", width=10)
        self.btn_show_sk.pack(side=tk.LEFT, padx=(10, 0))

        # 6. Session Token (Multiline text area)
        row_token_lbl = tk.Frame(main_frame, bg=BG_COLOR)
        row_token_lbl.pack(fill=tk.X, pady=(0, 5))
        
        lbl_token = tk.Label(row_token_lbl, text="Session Token:", font=("Segoe UI", 10, "bold"), fg=TEXT_COLOR, bg=BG_COLOR)
        lbl_token.pack(side=tk.LEFT)
        
        lbl_token_hint = tk.Label(row_token_lbl, text="(opcional - solo credenciales temporales STS/SSO)", 
                                  font=("Segoe UI", 9, "italic"), fg=TEXT_MUTED, bg=BG_COLOR)
        lbl_token_hint.pack(side=tk.LEFT, padx=(8, 0))
        
        token_frame = tk.Frame(main_frame, bg=INPUT_BORDER, bd=1, padx=1, pady=1)
        token_frame.pack(fill=tk.BOTH, expand=True, pady=(0, 15))
        
        self.text_token = tk.Text(token_frame, bg=INPUT_BG, fg=TEXT_COLOR, insertbackground=TEXT_COLOR, 
                                  font=("Courier New", 9), relief="flat", height=4, undo=True)
        self.text_token.pack(fill=tk.BOTH, expand=True)

        # Separator 3
        sep3 = tk.Frame(main_frame, bg=INPUT_BORDER, height=1)
        sep3.pack(fill=tk.X, pady=(0, 15))

        # 7. Core Actions (Save & Validate)
        row_actions = tk.Frame(main_frame, bg=BG_COLOR)
        row_actions.pack(fill=tk.X, pady=(0, 5))
        
        btn_save = self.create_flat_button(row_actions, "Guardar / Crear Perfil", self.on_btn_save, 
                                           ACCENT_BLUE, "#74c7ec", font=("Segoe UI", 11, "bold"), height=2)
        btn_save.pack(side=tk.LEFT, fill=tk.X, expand=True, marginRight=6)
        
        # Helper to simulate margins on tk.pack
        tk.Frame(row_actions, bg=BG_COLOR, width=12).pack(side=tk.LEFT)
        
        btn_test = self.create_flat_button(row_actions, "Validar Credenciales", self.on_btn_validate, 
                                           ACCENT_GREEN, "#a6e3a1", font=("Segoe UI", 11, "bold"), height=2, text_color="#1e1e2e")
        btn_test.pack(side=tk.LEFT, fill=tk.X, expand=True)

        # 8. Status Bar
        self.status_bar = tk.Label(self.root, text=f"Listo  |  {CRED_PATH}", bd=1, relief=tk.SUNKEN, 
                                   anchor=tk.W, font=("Segoe UI", 9), bg="#11111b", fg=TEXT_MUTED, padx=10, pady=4)
        self.status_bar.pack(side=tk.BOTTOM, fill=tk.X)

    # -------------------------------------------------------
    # WIDGET BUILDER HELPERS
    # -------------------------------------------------------
    def create_modern_entry(self, parent, show=None):
        frame = tk.Frame(parent, bg=INPUT_BORDER, bd=1, padx=1, pady=1)
        entry = tk.Entry(frame, bg=INPUT_BG, fg=TEXT_COLOR, insertbackground=TEXT_COLOR,
                         relief="flat", font=("Segoe UI", 10), show=show, bd=0)
        entry.pack(fill=tk.BOTH, expand=True, padx=5, pady=4)
        
        # Focus events for visual highlight border
        def on_focus_in(event):
            frame.configure(bg=ACCENT_BLUE)
        def on_focus_out(event):
            frame.configure(bg=INPUT_BORDER)
            
        entry.bind("<FocusIn>", on_focus_in)
        entry.bind("<FocusOut>", on_focus_out)
        return entry

    def create_flat_button(self, parent, text, command, bg, active_bg, font=("Segoe UI", 10, "bold"), 
                           width=None, height=None, text_color="#ffffff", marginRight=0):
        btn = tk.Button(parent, text=text, command=command, bg=bg, fg=text_color, 
                        activebackground=active_bg, activeforeground=text_color,
                        font=font, relief="flat", bd=0, cursor="hand2", 
                        highlightthickness=0, width=width, height=height)
        return btn

    # -------------------------------------------------------
    # LOGIC ACTIONS
    # -------------------------------------------------------
    def refresh_combo_profiles(self, select_profile=None):
        profiles = read_profiles()
        self.combo_profile['values'] = profiles
        if select_profile and select_profile in profiles:
            self.combo_profile.set(select_profile)
        else:
            self.combo_profile.set("")

    def on_profile_selected(self, event):
        profile = self.combo_profile.get()
        if not profile:
            return
        
        data = get_profile_data(profile)
        
        # Update inputs
        self.set_entry_text(self.entry_profile, profile)
        self.set_entry_text(self.entry_ak, data.get("aws_access_key_id", ""))
        self.set_entry_text(self.entry_sk, data.get("aws_secret_access_key", ""))
        
        # Reset password visibility
        self.entry_sk.configure(show="•")
        self.btn_show_sk.configure(text="Ver")
        
        # Set Session Token
        self.text_token.delete("1.0", tk.END)
        self.text_token.insert("1.0", data.get("aws_session_token", ""))
        
        self.set_status(f"Perfil cargado: '{profile}'  |  {CRED_PATH}")

    def on_btn_nuevo(self):
        self.combo_profile.set("")
        self.set_entry_text(self.entry_profile, "")
        self.set_entry_text(self.entry_ak, "")
        self.set_entry_text(self.entry_sk, "")
        self.text_token.delete("1.0", tk.END)
        
        self.entry_sk.configure(show="•")
        self.btn_show_sk.configure(text="Ver")
        
        self.set_status("Formulario limpio. Introduce los datos del nuevo perfil.")
        self.entry_profile.focus_set()

    def on_btn_eliminar(self):
        profile = self.entry_profile.get().strip()
        if not profile:
            messagebox.showwarning("Aviso", "Selecciona un perfil para eliminar.")
            return
            
        confirm = messagebox.askyesno(
            "Confirmar eliminación",
            f"¿Estás seguro de que deseas eliminar permanentemente el perfil '{profile}'?",
            default=messagebox.NO
        )
        if confirm:
            remove_profile_data(profile)
            self.refresh_combo_profiles()
            self.on_btn_nuevo()
            messagebox.showinfo("Eliminado", f"Perfil '{profile}' eliminado correctamente.")

    def on_btn_save(self):
        profile = self.entry_profile.get().strip()
        if not profile:
            messagebox.showwarning("Aviso", "Introduce un nombre de perfil antes de guardar.")
            self.entry_profile.focus_set()
            return
            
        if any(c.isspace() for c in profile):
            messagebox.showwarning("Aviso", "El nombre del perfil no puede contener espacios.")
            self.entry_profile.focus_set()
            return
            
        ak = self.entry_ak.get().strip()
        sk = self.entry_sk.get().strip()
        token = self.text_token.get("1.0", tk.END).strip()
        
        if not ak or not sk:
            messagebox.showwarning("Aviso", "El Access Key ID y el Secret Access Key son obligatorios.")
            return
            
        # Perform save
        save_profile_data(profile, ak, sk, token)
        self.refresh_combo_profiles(select_profile=profile)
        self.set_status(f"Perfil '{profile}' guardado.  Archivo: {CRED_PATH}")
        
        messagebox.showinfo(
            "Guardado",
            f"Perfil '{profile}' guardado correctamente.\n\nArchivo: {CRED_PATH}"
        )

    def on_btn_validate(self):
        profile = self.entry_profile.get().strip()
        if not profile:
            messagebox.showwarning("Aviso", "Selecciona o escribe un nombre de perfil antes de validar.")
            return

        # Check for unsaved changes
        if self.is_dirty(profile):
            resp = messagebox.askyesnocancel(
                "Cambios pendientes",
                f"Hay cambios sin guardar en el perfil '{profile}'.\n\n¿Deseas guardarlos antes de validar?"
            )
            if resp is None:  # Cancel
                return
            if resp:  # Yes
                ak = self.entry_ak.get().strip()
                sk = self.entry_sk.get().strip()
                token = self.text_token.get("1.0", tk.END).strip()
                if not ak or not sk:
                    messagebox.showwarning("Aviso", "El Access Key ID y el Secret Access Key son obligatorios.")
                    return
                save_profile_data(profile, ak, sk, token)
                self.refresh_combo_profiles(select_profile=profile)

        self.set_status(f"Validando perfil '{profile}'...")
        self.root.config(cursor="watch")
        self.root.update_idletasks()
        
        try:
            valid, msg = validate_credentials_cli(profile)
            if valid:
                messagebox.showinfo("Validación correcta", msg)
            else:
                messagebox.showwarning("Error de validación", msg)
        finally:
            self.root.config(cursor="")
            self.set_status(f"Listo.  Archivo: {CRED_PATH}")

    # -------------------------------------------------------
    # UTILITY HELPERS
    # -------------------------------------------------------
    def is_dirty(self, profile):
        saved = get_profile_data(profile)
        saved_ak = saved.get("aws_access_key_id", "")
        saved_sk = saved.get("aws_secret_access_key", "")
        saved_token = saved.get("aws_session_token", "")
        
        current_ak = self.entry_ak.get().strip()
        current_sk = self.entry_sk.get().strip()
        current_token = self.text_token.get("1.0", tk.END).strip()
        
        return (current_ak != saved_ak) or (current_sk != saved_sk) or (current_token != saved_token)

    def toggle_sk_visibility(self):
        if self.entry_sk.cget("show") == "•":
            self.entry_sk.configure(show="")
            self.btn_show_sk.configure(text="Ocultar")
        else:
            self.entry_sk.configure(show="•")
            self.btn_show_sk.configure(text="Ver")

    def set_entry_text(self, entry, text):
        entry.delete(0, tk.END)
        entry.insert(0, text)

    def set_status(self, text):
        self.status_bar.configure(text=text)


if __name__ == "__main__":
    root = tk.Tk()
    app = AwsConfigureGuiApp(root)
    root.mainloop()
