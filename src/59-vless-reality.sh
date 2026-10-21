# Native architecture: ordinary protocols use src/19-splicore.sh.

nobrand_run_vless_reality_action() {
  case "${VLESS_REALITY_ACTION:-menu}" in
    menu) vless_reality_menu_loop ;;
    help) nobrand_usage ;;
    *) nb_splicore_protocol vless-reality "${VLESS_REALITY_ACTION:-status}" "${VLESS_REALITY_NAME:-}" ;;
  esac
}
