package com.julianamarques.galaxybridge.bridge

import android.os.Bundle
import android.os.Parcelable

inline fun <reified T : Parcelable> Bundle.parcelable(key: String): T? = getParcelable(key, T::class.java)

inline fun <reified T : Parcelable> Bundle.parcelables(key: String): List<T> = getParcelableArrayList(key, T::class.java).orEmpty()
