do_perf() {
  t '========== 网络诊断（只读） ==========' '========== Network diagnostics (read only) =========='
  nb_splicore_call status || return 1
  report_bbr_fq_status
  ip -brief address show 2>/dev/null || true
  ip route show default 2>/dev/null || true
}
