import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_paytabs_bridge/BaseBillingShippingInfo.dart' as payTab;
import 'package:flutter_paytabs_bridge/IOSThemeConfiguration.dart';
import 'package:flutter_paytabs_bridge/PaymentSdkApms.dart';
import 'package:flutter_paytabs_bridge/PaymentSdkConfigurationDetails.dart';
import 'package:flutter_paytabs_bridge/flutter_paytabs_bridge.dart';
import 'package:payhere_mobilesdk_flutter/payhere_mobilesdk_flutter.dart';

import '../utils/Extensions/dataTypeExtensions.dart';
import '../../main.dart';
import '../../network/RestApis.dart';
import '../../utils/Colors.dart';
import '../../utils/Common.dart';
import '../../utils/Constants.dart';
import '../../utils/Extensions/AppButtonWidget.dart';
import '../../utils/Extensions/app_common.dart';
import '../model/PaymentListModel.dart';
import '../utils/images.dart';

class PaymentScreen extends StatefulWidget {
  final int? amount;

  PaymentScreen({this.amount});

  @override
  PaymentScreenState createState() => PaymentScreenState();
}

class PaymentScreenState extends State<PaymentScreen> {
  List<PaymentModel> paymentList = [];

  String? selectedPaymentType,
      payTabsProfileId,
      payTabsServerKey,
      payTabsClientKey;

  bool isTestType = true;
  bool loading = false;

  @override
  void initState() {
    super.initState();
    init();
  }

  void init() async {
    await paymentListApiCall();
  }

  Future<void> paymentListApiCall() async {
    appStore.setLoading(true);
    try {
      final value = await getPaymentList();
      appStore.setLoading(false);

      if (value.data != null) {
        paymentList.addAll(value.data!);
        if (paymentList.isNotEmpty) {
          selectedPaymentType = paymentList.first.type;
        }

        paymentList.forEach((element) {
          if (element.type == PAYMENT_TYPE_PAYTABS) {
            isTestType = element.isTest == 1;
            payTabsProfileId = isTestType
                ? element.testValue!.profileId
                : element.liveValue!.profileId;
            payTabsClientKey = isTestType
                ? element.testValue!.clientKey
                : element.liveValue!.clientKey;
            payTabsServerKey = isTestType
                ? element.testValue!.serverKey
                : element.liveValue!.serverKey;
          }
        });

        setState(() {});
      }
    } catch (error) {
      appStore.setLoading(false);
      log('Payment List Error: ${error.toString()}');
    }
  }

  String generateOrderId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = Random().nextInt(1000);
    return 'ORDER_${timestamp}_$random';
  }

  Future<void> paymentConfirm() async {
    Map req = {
      "user_id": sharedPref.getInt(USER_ID),
      "type": "credit",
      "amount": widget.amount,
      "transaction_type": "topup",
      "currency": "LKR",
    };

    try {
      appStore.isLoading = true;
      await saveWallet(req);
      appStore.isLoading = false;
      Navigator.pop(context, true);
    } catch (error) {
      appStore.isLoading = false;
      log(error.toString());
      toast("Payment confirmation failed: ${error.toString()}");
    }
  }

  void payTabsPayment() {
    FlutterPaytabsBridge.startCardPayment(generateConfig(), (event) {
      if (event["status"] == "success") {
        var transactionDetails = event["data"];
        if (transactionDetails["isSuccess"]) {
          toast("Transaction Successful!");
          paymentConfirm();
        } else {
          toast("Transaction Failed!");
        }
      } else if (event["status"] == "error") {
        toast("Payment Error: ${event["message"] ?? "Transaction Failed"}");
      } else if (event["status"] == "event") {
        // Handle other events
      }
    });
  }

  PaymentSdkConfigurationDetails generateConfig() {
    List<PaymentSdkAPms> apms = [];
    apms.add(PaymentSdkAPms.STC_PAY);

    var configuration = PaymentSdkConfigurationDetails(
        profileId: payTabsProfileId,
        serverKey: payTabsServerKey,
        clientKey: payTabsClientKey,
        cartDescription: "App Payment",
        screentTitle: "Pay with Card",
        amount: widget.amount!.toDouble(),
        showBillingInfo: true,
        forceShippingInfo: false,
        currencyCode: "LKR",
        merchantCountryCode: "LK",
        alternativePaymentMethods: apms,
        linkBillingNameWithCardHolderName: true);

    var theme = IOSThemeConfigurations();
    theme.logoImage = ic_logo_white;
    configuration.iOSThemeConfigurations = theme;

    return configuration;
  }

  Future<void> initiatePayherePayment() async {
    try {
      String orderId = generateOrderId();

      Map paymentObject = {
        "sandbox": isTestType, // Set to true for testing, false for production
        "merchant_id": payTabsProfileId ?? "",
        "merchant_secret": payTabsServerKey ?? "",
        "notify_url": payTabsClientKey, // Add your notification URL
        "order_id": orderId,
        "items": "App Payment",
        "amount": widget.amount!.toDouble(),
        "currency": "LKR",
        "first_name": sharedPref.getString(USER_NAME).validate(),
        "last_name": "",
        "email": sharedPref.getString(USER_EMAIL).validate(),
        "phone": sharedPref.getString(CONTACT_NUMBER).validate(),
        "address": sharedPref.getString(ADDRESS).validate(),
        "city": "",
        "country": "Sri Lanka",
        "delivery_address": sharedPref.getString(ADDRESS).validate(),
        "delivery_city": "Colombo",
        "delivery_country": "Sri Lanka",
        "custom_1": "",
        "custom_2": ""
      };

      PayHere.startPayment(
        paymentObject,
        (paymentId) {
          log("Payhere Payment Success: $paymentId");
          paymentConfirm();
        },
        (error) {
          log("Payhere Payment Error: $error");
          toast("Payment Failed: $error");
        },
        () {
          log("Payhere Payment Dismissed");
          toast("Payment Cancelled");
        },
      );
    } catch (e) {
      log("Payment initiation error: $e");
      toast("Failed to initiate payment: $e");
    }
  }

  void handlePayment() {
    if (selectedPaymentType == PAYMENT_TYPE_PAYTABS) {
      initiatePayherePayment();
    } else {
      initiatePayherePayment();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Payment",
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            )),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Select Payment Method",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 16),
                if (paymentList.isNotEmpty)
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: paymentList.map((e) {
                      return InkWell(
                        onTap: () {
                          selectedPaymentType = e.type;
                          setState(() {});
                        },
                        child: Container(
                          width: (MediaQuery.of(context).size.width - 48) / 2,
                          padding: EdgeInsets.symmetric(
                              horizontal: 12, vertical: 16),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: selectedPaymentType == e.type
                                    ? primaryColor
                                    : Colors.grey.withOpacity(0.5)),
                          ),
                          child: Row(
                            children: [
                              Image.network(
                                e.gatewayLogo!,
                                width: 40,
                                height: 40,
                                errorBuilder: (context, error, stackTrace) =>
                                    Icon(Icons.payment, size: 40),
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  e.title.validate(),
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                if (isTestType) ...[
                  SizedBox(height: 16),
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.yellow.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.orange),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "Test Mode Active - Use test card details",
                            style: TextStyle(color: Colors.orange[800]),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          Observer(builder: (context) {
            return Visibility(
              visible: appStore.isLoading,
              child: Container(
                color: Colors.black26,
                child: Center(child: CircularProgressIndicator()),
              ),
            );
          }),
          if (!appStore.isLoading && paymentList.isEmpty)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.payment_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    "No payment methods available",
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ],
              ),
            ),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Amount: ${widget.amount} LKR',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 16),
            Visibility(
              visible: paymentList.isNotEmpty,
              child: AppButtonWidget(
                text: "Pay Now",
                onTap: handlePayment,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
