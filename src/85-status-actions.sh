do_bbr_config() {
  require_root || return 1
  require_linux || return 1
  report_bbr_fq_status
  offer_bbr_fq
}
