# Native architecture: ordinary protocols use src/19-splicore.sh.

nobrand_run_tuic_action() {
  case "${TUIC_ACTION:-menu}" in
    menu) tuic_menu_loop ;;
    help) nobrand_usage ;;
    *) nb_splicore_protocol tuic "${TUIC_ACTION:-status}" "${TUIC_NAME:-}" ;;
  esac
}
