# Native architecture: ordinary protocols use src/19-splicore.sh.

do_user_manage() {
  local choice="" operation="" selector=""
  while true; do
    msg '【Mieru 节点】一个运行时管理多个节点 / Mieru nodes'
    msg '  1) 列出节点'
    msg '  2) 添加节点'
    msg '  3) 删除节点'
    msg '  4) 导出客户端配置'
    msg '  5) 启用节点'
    msg '  6) 停用节点'
    msg '  7) 设置展示端点'
    msg '  0) 返回'
    read_tty choice '请选择 [0-7]: ' || return 0
    selector=""
    case "$choice" in
      0) return 0 ;;
      1) operation=status ;;
      2)
        operation=install
        PORT="" PORT_CLI=0 USERNAME="" PASSWORD=""
        ADVERTISE_HOST="" ADVERTISE_PORT="" ADVERTISE_CLI=0 ADVERTISE_AUTO_REQUESTED=0
        read_tty USERNAME '新节点名: ' || continue
        read_tty PASSWORD '密码（回车随机）: ' || continue
        selector="$USERNAME"
        ;;
      3|4|5|6|7)
        nb_splicore_menu_select mieru || continue
        selector="$NOBRAND_MENU_SELECTION_ID"
        case "$choice" in 3) operation=remove ;; 4) operation=show ;; 5) operation=start ;; 6) operation=stop ;; 7) operation=set-endpoint; ADVERTISE_CLI=0 ;; esac
        ;;
      *) continue ;;
    esac
    YES=0
    nobrand_menu_run nb_splicore_protocol mieru "$operation" "$selector"
  done
}
