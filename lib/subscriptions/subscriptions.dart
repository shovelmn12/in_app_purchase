import 'package:rxdart/rxdart.dart';

import 'iap.dart';

const kMonthlySubscriptionSKU = "app.subscriptions.1";

class SubscriptionsSDK {
  InAppPurchasesPlugin get _iap => const InAppPurchaseConnectionPlugin();

  Stream<bool> get onChanged => Rx.concat([
        Stream.fromFuture(_iap.isSubscribed),
        _iap.onChange,
      ]).distinct();

  Future<bool> get isSubscribed => _iap.isSubscribed;

  const SubscriptionsSDK();

  Future<bool> subscribe(String sku) => _iap.subscribe(sku);

  Future<bool> restoreSubscription() => isSubscribed;
}
