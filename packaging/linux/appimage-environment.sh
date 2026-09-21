# Sourced by AppRun and host-command. Keep user session settings for host tools.
comfer_environment_variables='LD_LIBRARY_PATH LD_PRELOAD PATH XDG_DATA_DIRS GSETTINGS_SCHEMA_DIR GIO_MODULE_DIR GIO_EXTRA_MODULES GTK_PATH GTK_THEME GTK_EXE_PREFIX GTK_DATA_PREFIX GTK_IM_MODULE_FILE GDK_PIXBUF_MODULE_FILE GDK_PIXBUF_MODULEDIR GI_TYPELIB_PATH GDK_BACKEND'
comfer_save_host_environment() {
  local name saved marker
  for name in $comfer_environment_variables; do
    saved="COMFER_HOST_$name"; marker="${saved}_SET"
    if [[ -v "$name" ]]; then
      printf -v "$saved" '%s' "${!name}"
      printf -v "$marker" '1'
      export "$saved"
    else
      unset "$saved"
      printf -v "$marker" '0'
    fi
    export "$marker"
  done
}
comfer_restore_host_environment() {
  local name saved marker
  for name in $comfer_environment_variables; do
    saved="COMFER_HOST_$name"; marker="${saved}_SET"
    if [[ "${!marker}" == 1 ]]; then
      printf -v "$name" '%s' "${!saved}"
      export "$name"
    else
      unset "$name"
    fi
  done
}
