# ---------- Native Sudoku on the shared Splicore daemon ----------

nobrand_run_vless_sudoku_action() {
  local operation="${VLESS_SUDOKU_ACTION:-menu}" selector=primary
  case "$operation" in
    menu) vless_sudoku_menu_loop; return $? ;;
    help) nobrand_usage; return $? ;;
    smoke) operation=doctor ;;
    subscription) selector="" ;;
  esac
  nb_splicore_protocol vless-sudoku "$operation" "$selector"
}
