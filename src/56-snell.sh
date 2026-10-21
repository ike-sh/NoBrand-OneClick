# Native architecture: ordinary protocols use src/19-splicore.sh.

nobrand_run_snell_action() {
  case "${SNELL_ACTION:-menu}" in
    menu) snell_menu_loop ;;
    help) nobrand_usage ;;
    *) nb_splicore_protocol snell "${SNELL_ACTION:-status}" "${SNELL_NAME:-}" ;;
  esac
}
