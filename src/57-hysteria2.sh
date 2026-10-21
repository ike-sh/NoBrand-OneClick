# Native architecture: ordinary protocols use src/19-splicore.sh.

nobrand_run_hy2_action() {
  case "${HY2_ACTION:-menu}" in
    menu) hysteria2_menu_loop ;;
    help) nobrand_usage ;;
    *) nb_splicore_protocol hysteria2 "${HY2_ACTION:-status}" "hy2" ;;
  esac
}
