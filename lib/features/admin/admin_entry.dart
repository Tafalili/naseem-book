// Entry point of the admin panel, loaded on demand (deferred import) so the
// storefront bundle stays small.
import 'package:material_ui/material_ui.dart';

import 'admin_order_page.dart';
import 'admin_orders_page.dart';
import 'admin_products_page.dart';
import 'admin_settings_page.dart';
import 'admin_shell.dart';
import 'template_editor_page.dart';

Widget adminPage(String location, {String? orderId}) {
  final Widget child;
  if (orderId != null) {
    child = AdminOrderPage(id: orderId);
  } else if (location.startsWith(AdminRoutes.products)) {
    child = const AdminProductsPage();
  } else if (location.startsWith(AdminRoutes.templates)) {
    child = const TemplateEditorPage();
  } else if (location.startsWith(AdminRoutes.settings)) {
    child = const AdminSettingsPage();
  } else {
    child = const AdminOrdersPage();
  }
  return AdminShell(location: location, child: child);
}
