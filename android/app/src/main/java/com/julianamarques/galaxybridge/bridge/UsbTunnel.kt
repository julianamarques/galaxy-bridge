package com.julianamarques.galaxybridge.bridge

import android.content.Context
import android.hardware.usb.UsbAccessory
import android.hardware.usb.UsbManager
import android.os.ParcelFileDescriptor
import com.julianamarques.galaxybridge.Diagnostics
import java.io.BufferedInputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException
import java.net.InetAddress
import java.nio.ByteBuffer
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger
import kotlin.concurrent.thread

object UsbTunnel {
    const val MANUFACTURER = "Galaxy Bridge"
    const val MODEL = "Galaxy Bridge"
    private const val OPEN: Int = 0
    private const val DATA: Int = 1
    private const val CLOSE: Int = 2
    private const val PAD: Int = 3
    private const val RESET: Int = 4
    private const val HEADER = 7
    private const val PACKET = 512
    private const val CHUNK = 16 * 1024
    private const val USB_BUFFER = 16 * 1024

    @Volatile var port: Int? = null
        private set

    @Volatile var onChange: (() -> Unit)? = null

    @Volatile var readyAt = 0L
        private set

    private var accessory: UsbAccessory? = null
    private var descriptor: ParcelFileDescriptor? = null
    private var server: ServerSocket? = null
    private var output: DataOutputStream? = null
    private val channels = ConcurrentHashMap<Int, Socket>()
    private val nextChannel = AtomicInteger(1)

    val isActive: Boolean get() = port != null

    fun attachIfPresent(context: Context) {
        if (isActive) return
        val usb = context.getSystemService(UsbManager::class.java)
        usb.accessoryList?.firstOrNull { isOurs(it) && usb.hasPermission(it) }?.let { start(context, it) }
    }

    fun isOurs(accessory: UsbAccessory): Boolean = accessory.manufacturer == MANUFACTURER && accessory.model == MODEL

    @Synchronized
    fun start(context: Context, accessory: UsbAccessory) {
        if (this.accessory == accessory && isActive) return
        stop()
        val descriptor = context.getSystemService(UsbManager::class.java).openAccessory(accessory) ?: return
        val input = DataInputStream(BufferedInputStream(FileInputStream(descriptor.fileDescriptor), USB_BUFFER))
        val output = DataOutputStream(FileOutputStream(descriptor.fileDescriptor))
        val server = ServerSocket(0, 16, InetAddress.getByName(BridgeConnection.LOOPBACK))
        this.accessory = accessory
        this.descriptor = descriptor
        this.output = output
        this.server = server
        port = server.localPort
        readyAt = System.currentTimeMillis()
        Diagnostics.record(context, "Cabo USB conectado ao Mac")
        thread(name = "usb-read") { readUsb(input, context) }
        thread(name = "usb-accept") { accept(server) }
        onChange?.invoke()
    }

    @Synchronized
    fun stop() {
        if (accessory == null) return
        port = null
        accessory = null
        runCatching { server?.close() }
        server = null
        channels.values.forEach { runCatching { it.close() } }
        channels.clear()
        runCatching { descriptor?.close() }
        descriptor = null
        output = null
        onChange?.invoke()
    }

    private fun accept(server: ServerSocket) {
        while (!server.isClosed) {
            val socket = runCatching { server.accept() }.getOrNull() ?: break
            socket.tcpNoDelay = true
            val channel = nextChannel.getAndIncrement() and 0xFFFF
            channels[channel] = socket
            if (!write(OPEN, channel, ByteArray(0), 0)) {
                runCatching { socket.close() }
                break
            }
            thread(name = "usb-channel-$channel") { pump(channel, socket) }
        }
    }

    private fun pump(channel: Int, socket: Socket) {
        val buffer = ByteArray(CHUNK)
        try {
            val input = socket.getInputStream()
            while (true) {
                val count = input.read(buffer)
                if (count < 0 || !write(DATA, channel, buffer, count)) break
            }
        } catch (_: IOException) {
        }
        if (channels.remove(channel) != null) {
            runCatching { socket.close() }
            write(CLOSE, channel, ByteArray(0), 0)
        }
    }

    private fun readUsb(input: DataInputStream, context: Context) {
        try {
            while (true) {
                val type = input.readUnsignedByte()
                val channel = input.readUnsignedShort()
                val length = input.readInt()
                val payload = ByteArray(length).also(input::readFully)
                if (type == RESET) {
                    channels.values.forEach { runCatching { it.close() } }
                    channels.clear()
                    readyAt = System.currentTimeMillis()
                    onChange?.invoke()
                    continue
                }
                val socket = channels[channel] ?: continue
                when (type) {
                    DATA -> runCatching { socket.getOutputStream().write(payload) }.onFailure { close(channel) }
                    CLOSE -> {
                        channels.remove(channel)
                        runCatching { socket.close() }
                    }
                }
            }
        } catch (_: IOException) {
        }
        Diagnostics.record(context, "Cabo USB desconectado do Mac")
        stop()
    }

    private fun header(frame: ByteArray, at: Int, type: Int, channel: Int, length: Int) {
        ByteBuffer.wrap(frame, at, HEADER).put(type.toByte()).putShort(channel.toShort()).putInt(length)
    }

    private fun close(channel: Int) {
        channels.remove(channel)?.let { runCatching { it.close() } }
        write(CLOSE, channel, ByteArray(0), 0)
    }

    private fun write(type: Int, channel: Int, payload: ByteArray, length: Int): Boolean {
        val output = output ?: return false
        val padded = (HEADER + length) % PACKET == 0
        val frame = ByteArray(HEADER + length + if (padded) HEADER else 0)
        header(frame, 0, type, channel, length)
        payload.copyInto(frame, HEADER, 0, length)
        if (padded) header(frame, HEADER + length, PAD, 0, 0)
        return try {
            synchronized(output) {
                output.write(frame)
                output.flush()
            }
            true
        } catch (_: IOException) {
            false
        }
    }
}
