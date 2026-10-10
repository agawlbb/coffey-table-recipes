import 'dart:js_interop';

@JS('window.open')
external JSObject? _open(String url, String target, String features);

bool openAdministrationWindow() =>
    _open('#/administration', '_blank', 'popup,width=1000,height=760') != null;
