plugins {
    alias(libs.plugins.android.asset.pack)
}

assetPack {
    packName.set("hapondani_model_pack_1")
    dynamicDelivery {
        deliveryType.set("fast-follow")
    }
}
