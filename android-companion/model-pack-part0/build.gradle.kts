plugins {
    alias(libs.plugins.android.asset.pack)
}

assetPack {
    packName.set("hapondani_model_pack_0")
    dynamicDelivery {
        deliveryType.set("fast-follow")
    }
}
