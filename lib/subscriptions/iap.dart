import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase/store_kit_wrappers.dart';

const kSharedIosKey = "my_key";
const kProductionVerifyReceiptBase = "https://buy.itunes.apple.com";
const kTestFlightVerifyReceiptBase = "https://sandbox.itunes.apple.com";

Future<bool> _validateIOSReceipt(String base, String receipt) async {
  try {
    final response = await Dio().post<Map<String, dynamic>>(
      "$base/verifyReceipt",
      data: {
        "receipt-data": receipt,
        "password": kSharedIosKey,
        "exclude-old-transactions": true,
      },
    );

    print("_validateIOSReceipt data ${response.data}");

    if (response.data == null) {
      return false;
    }

    final latest = List<Map<String, dynamic>>.from(
        response.data["latest_receipt_info"] ?? const []);

    print("_validateIOSReceipt latest $latest");

    if (latest.isEmpty) {
      return false;
    }

    final now = DateTime.now().millisecondsSinceEpoch;

    return latest.map((receipt) {
      final expires = int.parse(receipt["expires_date_ms"]);
      final valid = expires > now;

      print("$expires > $now = $valid");

      return valid;
    }).firstWhere(
      (notExpired) => notExpired,
      orElse: () => false,
    );
  } catch (e, stack) {
    print("$e $stack");

    return false;
  }
}

abstract class InAppPurchasesPlugin<P, I> {
  Stream<bool> get onChange;

  Future<bool> get isSubscribed;

  const InAppPurchasesPlugin();

  @protected
  Future<bool> validateAndroid(P purchase);

  @protected
  Future<bool> validateIOS(P purchase);

  Future<bool> validate(P purchase);

  Future<I> getItem(String id);

  Future<bool> subscribe(String plan);
}

class InAppPurchaseConnectionPlugin
    extends InAppPurchasesPlugin<PurchaseDetails, ProductDetails> {
  InAppPurchaseConnection get _iap => InAppPurchaseConnection.instance;

  const InAppPurchaseConnectionPlugin();

  @override
  Future<bool> get isSubscribed => _iap
      .queryPastPurchases()
      .then((result) => Future.wait(result.pastPurchases.map(validate))
          .then((value) => value.orSum()))
      .catchError((_) => false);

  @override
  Stream<bool> get onChange => _iap.purchaseUpdatedStream
      .asyncMap((purchases) => Future.wait(purchases.map(validate)))
      .map((purchases) => purchases.orSum())
      .distinct();

  @override
  Future<bool> subscribe(String plan) async {
    if (Platform.isIOS) {
      print("clearing past subscriptions");
      final paymentWrapper = SKPaymentQueueWrapper();
      final transactions = await paymentWrapper.transactions();

      await Future.wait(transactions
          .map((transaction) => paymentWrapper.finishTransaction(transaction)));
    }

    return await _iap.buyNonConsumable(
      purchaseParam: PurchaseParam(
        productDetails: await getItem(plan),
      ),
    );
  }

  @override
  Future<bool> validate(PurchaseDetails purchase) async {
    if (Platform.isAndroid) {
      return await validateAndroid(purchase);
    } else if (Platform.isIOS) {
      return await validateIOS(purchase);
    }

    return false;
  }

  @override
  Future<ProductDetails> getItem(String id) async {
    final result = await _iap.queryProductDetails({id});

    if (result.notFoundIDs?.isNotEmpty ?? false) {
      return null;
    }

    return result.productDetails[0];
  }

  @override
  Future<bool> validateAndroid(PurchaseDetails purchase) async {
    if (purchase.pendingCompletePurchase) {
      await _iap.completePurchase(purchase);
    }

    return purchase.status == PurchaseStatus.purchased;
  }

  @override
  Future<bool> validateIOS(PurchaseDetails purchase) async {
    if (purchase.pendingCompletePurchase) {
      await _iap.completePurchase(purchase);
    }

    final validProdReceipt = await _validateIOSReceipt(
      kProductionVerifyReceiptBase,
      purchase.verificationData.serverVerificationData,
    );

    if (validProdReceipt) {
      return true;
    }

    return await _validateIOSReceipt(
      kTestFlightVerifyReceiptBase,
      purchase.verificationData.serverVerificationData,
    );
  }
}
//
// class FlutterInAppPurchasePlugin
//     extends InAppPurchasesPlugin<PurchasedItem, IAPItem> {
//   FlutterInappPurchase get _iap => FlutterInappPurchase.instance;
//
//   const FlutterInAppPurchasePlugin();
//
//   @override
//   Future<bool> get isSubscribed =>
//       _iap.getAvailablePurchases().then((purchases) {
//         print("isSubscribed $purchases");
//
//         return Future.wait(purchases.map(validate))
//             .then((value) => value.orSum());
//       }).catchError((_) => false);
//
//   @override
//   Stream<bool> get onChange =>
//       FlutterInappPurchase.purchaseUpdated.asyncMap((purchase) {
//         print("purchaseUpdated $purchase");
//
//         return validate(purchase);
//       }).distinct();
//
//   @override
//   Future<bool> subscribe(String plan) async {
//     print("subscribe $plan");
//     return await _iap.requestSubscription(plan).catchError(print);
//   }
//
//   @override
//   Future<bool> validate(PurchasedItem purchase) async {
//     if (Platform.isAndroid) {
//       return await validateAndroid(purchase);
//     } else if (Platform.isIOS) {
//       return await validateIOS(purchase);
//     }
//
//     return false;
//   }
//
//   @override
//   Future<IAPItem> getItem(String id) async {
//     final result = await _iap.getProducts([id]);
//
//     if (result?.isEmpty ?? true) {
//       return null;
//     }
//
//     return result[0];
//   }
//
//   @override
//   Future<bool> validateAndroid(PurchasedItem purchase) async {
//     if (!purchase.isAcknowledgedAndroid) {
//       await _iap.acknowledgePurchaseAndroid(purchase.purchaseToken);
//     }
//
//     return purchase.purchaseStateAndroid == PurchaseState.purchased;
//   }
//
//   @override
//   Future<bool> validateIOS(PurchasedItem purchase) async {
//     final validState =
//         purchase.transactionStateIOS == TransactionState.purchased ||
//             purchase.transactionStateIOS == TransactionState.restored;
//
//     await _iap.finishTransactionIOS(purchase.transactionId);
//
//     if (!validState) {
//       return false;
//     }
//
//     final validProdReceipt = await _validateIOSReceipt(
//       kProductionVerifyReceiptBase,
//       purchase.transactionReceipt,
//     );
//
//     if (validProdReceipt) {
//       return true;
//     }
//
//     return await _validateIOSReceipt(
//       kTestFlightVerifyReceiptBase,
//       purchase.transactionReceipt,
//     );
//   }
// }

extension IterableBoolExtension<T extends bool> on Iterable<T> {
  bool andSum() {
    if (isEmpty) {
      return false;
    }

    return reduce((value, element) => value && element);
  }

  bool orSum() {
    if (isEmpty) {
      return false;
    }

    final result = firstWhere(
      (element) => element,
      orElse: () => null,
    );

    return result == true;
  }
}
