package com.nahuelwagner.splg.driver

import android.app.Application
import com.pravera.flutter_foreground_task.models.ForegroundServiceAction
import com.pravera.flutter_foreground_task.models.ForegroundServiceStatus
import com.pravera.flutter_foreground_task.service.RestartReceiver

/**
 * Desarma el reinicio automático del servicio en primer plano de
 * flutter_foreground_task.
 *
 * El servicio es de tipo location y se arranca sin callback de Dart: sólo
 * sirve para que Android no mate el proceso donde viven el socket y el GPS de
 * la app. Cuando el proceso muere (por ejemplo, porque se revocó el permiso de
 * ubicación) el plugin lo vuelve a levantar solo (START_STICKY, alarma de
 * reinicio, arranque tras el boot) y llama a startForeground sin preguntar por
 * el permiso: Android tira SecurityException en el hilo principal y la app se
 * cierra en bucle. Un servicio revivido así, además, no tiene motor de Dart.
 *
 * Al nacer el proceso el servicio nunca está corriendo, así que se lo deja
 * como detenido: si Android lo reinicia, el plugin ve API_STOP y se detiene
 * sin llamar a startForeground. El único que lo arranca es la app
 * (DriverForegroundService.start), después de verificar el permiso.
 */
class SplgDriverApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        ForegroundServiceStatus.setData(this, ForegroundServiceAction.API_STOP)
        RestartReceiver.cancelRestartAlarm(this)
    }
}
