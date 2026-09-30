package com.example.zhixi

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Bundle
import java.util.concurrent.ConcurrentHashMap

class TermuxResultReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getIntExtra("requestId", -1)
        pending.remove(id)?.invoke(intent.getBundleExtra("result"))
    }

    companion object {
        val pending = ConcurrentHashMap<Int, (Bundle?) -> Unit>()
    }
}
