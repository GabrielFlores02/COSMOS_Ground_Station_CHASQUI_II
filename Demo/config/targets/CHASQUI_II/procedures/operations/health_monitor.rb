# ============================================================================
# SCRIPT 10: HEALTH MONITOR CONTINUO
# ============================================================================
# Archivo: procedures/operations/health_monitor.rb

load_utility 'ground_station_library'

def continuous_health_monitor(interval_sec: 60, alert_threshold: 3)
  puts "="*70
  puts "MONITOR CONTINUO DE SALUD"
  puts "="*70
  puts "Intervalo: #{interval_sec}s"
  puts "Umbral de alerta: #{alert_threshold} alertas"
  puts "Presione Ctrl+C para detener"
  puts "="*70 + "\n"
  
  alert_count = 0
  last_voltage = 0
  samples_collected = 0
  
  # Crear archivo de log
  log_file = File.join(Cosmos::USERPATH, 'outputs', 'logs', 
                        "health_monitor_#{Time.now.strftime('%Y%m%d_%H%M%S')}.csv")
  
  File.open(log_file, 'w') do |f|
    f.puts "Timestamp,Voltage,Current,SoC_Avg,Temp_CDH,Temp_EPS,Temp_Bat,Mode,Alerts"
  end
  
  puts "Log: #{log_file}\n"
  
  loop do
    begin
      timestamp = Time.now
      
      # Obtener telemetría
      voltage = tlm("CHASQUI_II BEACON MAIN_BATT_VOLT")
      current = tlm("CHASQUI_II BEACON MAIN_BATT_CURR")
      temp_cdh = tlm("CHASQUI_II BEACON TEMP_CDH")
      temp_eps = tlm("CHASQUI_II BEACON TEMP_EPS")
      temp_bat = tlm("CHASQUI_II BEACON TEMP_BAT_TH1")
      mode = tlm("CHASQUI_II BEACON SAT_CURR_MODE")
      
      soc1 = tlm("CHASQUI_II BEACON EPS_FG1_SOC")
      soc2 = tlm("CHASQUI_II BEACON EPS_FG2_SOC")
      soc3 = tlm("CHASQUI_II BEACON EPS_FG3_SOC")
      soc_avg = (soc1 + soc2 + soc3) / 3.0
      
      samples_collected += 1
      
      # Verificar alertas
      alerts = []
      
      if voltage < 7.0
        alerts << "Voltaje CRÍTICO: #{voltage.round(2)}V"
      elsif voltage < 7.5
        alerts << "Voltaje bajo: #{voltage.round(2)}V"
      end
      
      if temp_cdh > 50
        alerts << "Temp CDH alta: #{temp_cdh.round(1)}°C"
      elsif temp_cdh < -10
        alerts << "Temp CDH baja: #{temp_cdh.round(1)}°C"
      end
      
      if temp_bat < 0
        alerts << "Batería fría: #{temp_bat.round(1)}°C"
      elsif temp_bat > 30
        alerts << "Batería caliente: #{temp_bat.round(1)}°C"
      end
      
      # Detectar caída de voltaje rápida
      if last_voltage > 0 && (last_voltage - voltage) > 0.3
        alerts << "Caída rápida de voltaje: #{(last_voltage - voltage).round(2)}V"
      end
      
      last_voltage = voltage
      
      # Mostrar en consola
      status_icon = alerts.any? ? "⚠" : "✓"
      
      puts "[#{timestamp.strftime('%H:%M:%S')}] #{status_icon} " \
           "V:#{voltage.round(2)}V " \
           "I:#{current.round(3)}A " \
           "SoC:#{soc_avg.round(1)}% " \
           "T:#{temp_cdh.round(1)}/#{temp_eps.round(1)}/#{temp_bat.round(1)}°C " \
           "#{mode}"
      
      # Mostrar alertas
      if alerts.any?
        alert_count += 1
        alerts.each { |alert| puts "  ⚠ #{alert}" }
        
        # Acción automática si se excede umbral
        if alert_count >= alert_threshold
          puts "\n⚠⚠⚠ UMBRAL DE ALERTAS EXCEDIDO (#{alert_count}) ⚠⚠⚠"
          puts "Considerar ejecutar recuperación de emergencia"
          puts "Ejecutar 'emergency_recovery.rb' si es necesario\n"
          
          alert_count = 0  # Reset contador
        end
      else
        # Reset contador si no hay alertas
        alert_count = 0
      end
      
      # Guardar en CSV
      File.open(log_file, 'a') do |f|
        f.puts "#{timestamp.iso8601},#{voltage},#{current},#{soc_avg}," \
               "#{temp_cdh},#{temp_eps},#{temp_bat},#{mode},\"#{alerts.join('; ')}\""
      end
      
      wait(interval_sec)
      
    rescue Interrupt
      puts "\n\n✓ Monitor detenido por usuario"
      break
      
    rescue => e
      puts "\n✗ Error: #{e.message}"
      puts "Reintentando en #{interval_sec}s..."
      wait(interval_sec)
    end
  end
  
  puts "\n" + "="*70
  puts "RESUMEN DEL MONITOR"
  puts "="*70
  puts "Muestras recolectadas: #{samples_collected}"
  puts "Log guardado: #{log_file}"
  puts "="*70
end

# Ejecución desde Script Runner
if __FILE__ == $0
  interval = ask("Intervalo de muestreo (segundos):").to_i
  continuous_health_monitor(interval_sec: interval)
end