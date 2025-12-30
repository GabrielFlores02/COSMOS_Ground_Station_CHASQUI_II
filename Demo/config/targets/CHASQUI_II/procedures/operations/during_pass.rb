# ============================================================================
# SCRIPT 2: DURANTE EL PASE (Monitoreo en Tiempo Real)
# ============================================================================
# Archivo: procedures/operations/during_pass.rb

load_utility 'ground_station_library'

def monitor_pass_real_time(auto_commands: true, auto_download: true)
  puts "="*70
  puts "MONITOREO EN TIEMPO REAL - PASE ACTIVO"
  puts "="*70
  puts "Comandos automáticos: #{auto_commands ? 'HABILITADO' : 'DESHABILITADO'}"
  puts "Descarga automática:  #{auto_download ? 'HABILITADO' : 'DESHABILITADO'}"
  puts "="*70
  
  # Variables de monitoreo
  packet_count = 0
  last_beacon_time = nil
  aos_confirmed = false
  health_alerts = []
  commands_log = []
  
  # Obtener configuración del pase
  pass_dir = get_global_variable("CURRENT_PASS_DIR")
  pass_duration = get_global_variable("PASS_DURATION")
  
  # Archivos de log
  monitor_log = File.join(pass_dir, 'logs', 'monitor.log')
  health_log = File.join(pass_dir, 'logs', 'health.log')
  commands_log_file = File.join(pass_dir, 'logs', 'commands.log')
  
  # Abrir archivos de log
  log_monitor = File.open(monitor_log, 'w')
  log_health = File.open(health_log, 'w')
  log_commands = File.open(commands_log_file, 'w')
  
  begin
    log_monitor.puts "MONITOREO DE PASE - INICIO: #{Time.now}"
    log_monitor.puts "="*70
    log_monitor.flush
    
    # Tiempo de inicio de monitoreo
    monitor_start = Time.now
    pass_end_time = monitor_start + (pass_duration * 60)
    
    puts "\n[MONITOR] Esperando AOS..."
    puts "Presione Ctrl+C para detener monitoreo manual\n"
    
    # Loop principal de monitoreo
    loop do
      current_time = Time.now
      
      # Verificar si se acabó el tiempo del pase
      if current_time > pass_end_time
        puts "\n[MONITOR] Tiempo de pase finalizado"
        break
      end
      
      begin
        # Esperar beacon con timeout de 30 segundos
        wait_packet("CHASQUI_II", "BEACON", 1, 30)
        
        packet_count += 1
        last_beacon_time = Time.now
        set_global_variable("PASS_PACKET_COUNT", packet_count)
        
        # Confirmar AOS en primer beacon
        if !aos_confirmed
          aos_confirmed = true
          aos_time = Time.now
          set_global_variable("PASS_AOS_TIME", aos_time)
          
          puts "\n" + "="*70
          puts "🛰️  AOS CONFIRMADO"
          puts "Tiempo: #{aos_time.strftime('%H:%M:%S')}"
          puts "="*70 + "\n"
          
          log_monitor.puts "\nAOS CONFIRMADO: #{aos_time}"
          log_monitor.flush
          
          # Ejecutar secuencia AOS
          if auto_commands
            puts "[AUTO] Ejecutando secuencia AOS..."
            execute_aos_sequence(log_commands)
          end
        end
        
        # Extraer telemetría
        voltage = tlm("CHASQUI_II BEACON MAIN_BATT_VOLT")
        current = tlm("CHASQUI_II BEACON MAIN_BATT_CURR")
        temp_cdh = tlm("CHASQUI_II BEACON TEMP_CDH")
        temp_eps = tlm("CHASQUI_II BEACON TEMP_EPS")
        mode = tlm("CHASQUI_II BEACON SAT_CURR_MODE")
        soc1 = tlm("CHASQUI_II BEACON EPS_FG1_SOC")
        soc2 = tlm("CHASQUI_II BEACON EPS_FG2_SOC")
        soc3 = tlm("CHASQUI_II BEACON EPS_FG3_SOC")
        soc_avg = (soc1 + soc2 + soc3) / 3.0
        
        # Mostrar en consola (cada 5 paquetes)
        if packet_count % 5 == 0
          elapsed = ((Time.now - monitor_start) / 60.0).round(1)
          puts "\n[#{Time.now.strftime('%H:%M:%S')}] Paquete ##{packet_count} (#{elapsed}min)"
          puts "  V: #{voltage.round(2)}V  I: #{current.round(3)}A  SoC: #{soc_avg.round(1)}%"
          puts "  T_CDH: #{temp_cdh.round(1)}°C  T_EPS: #{temp_eps.round(1)}°C  Modo: #{mode}"
        end
        
        # Log detallado de health
        log_health.puts "#{Time.now},#{voltage},#{current},#{temp_cdh},#{temp_eps},#{mode},#{soc_avg}"
        log_health.flush
        
        # Verificar condiciones de salud y alertas
        alerts = check_health_conditions(voltage, current, temp_cdh, temp_eps, mode)
        
        if alerts.any?
          alerts.each do |alert|
            puts "\n⚠ ALERTA: #{alert}"
            log_monitor.puts "ALERTA: #{alert}"
            health_alerts << {time: Time.now, alert: alert}
          end
          log_monitor.flush
          
          # Acciones automáticas en emergencia
          if auto_commands && alerts.any? { |a| a.include?("CRÍTICO") }
            puts "\n[AUTO] Iniciando recuperación de emergencia..."
            execute_emergency_recovery(log_commands)
          end
        end
        
        # Descarga automática de datos (cada 50 paquetes)
        if auto_download && aos_confirmed && packet_count % 50 == 0
          puts "\n[AUTO] Iniciando descarga automática..."
          execute_auto_download(log_commands)
        end
        
      rescue Timeout::Error
        # No se recibió beacon en 30 segundos
        if aos_confirmed
          timeout_duration = (Time.now - last_beacon_time).round(0)
          puts "\n[MONITOR] ⚠ Sin beacons por #{timeout_duration}s"
          
          if timeout_duration > 90
            puts "[MONITOR] Timeout prolongado - Posible LOS"
            log_monitor.puts "Timeout prolongado (#{timeout_duration}s) - Posible LOS"
            log_monitor.flush
            break
          end
        end
        
      rescue Interrupt
        puts "\n[MONITOR] Interrupción manual detectada"
        break
        
      rescue => e
        puts "\n[ERROR] #{e.message}"
        log_monitor.puts "ERROR: #{e.message}"
        log_monitor.flush
      end
    end
    
    # Finalización del pase
    los_time = Time.now
    set_global_variable("PASS_LOS_TIME", los_time)
    set_global_variable("PASS_HEALTH_ALERTS", health_alerts)
    
    puts "\n" + "="*70
    puts "📡 PASE FINALIZADO"
    puts "="*70
    puts "AOS:              #{get_global_variable('PASS_AOS_TIME')&.strftime('%H:%M:%S') || 'N/A'}"
    puts "LOS:              #{los_time.strftime('%H:%M:%S')}"
    puts "Paquetes:         #{packet_count}"
    puts "Alertas:          #{health_alerts.count}"
    puts "="*70
    
    log_monitor.puts "\n" + "="*70
    log_monitor.puts "PASE FINALIZADO: #{los_time}"
    log_monitor.puts "Total paquetes: #{packet_count}"
    log_monitor.puts "Total alertas: #{health_alerts.count}"
    log_monitor.puts "="*70
    
  ensure
    # Cerrar archivos
    log_monitor.close
    log_health.close
    log_commands.close
  end
  
  return {
    packets: packet_count,
    alerts: health_alerts.count,
    aos: get_global_variable("PASS_AOS_TIME"),
    los: los_time
  }
end

# Helper: Verificar condiciones de salud
def check_health_conditions(voltage, current, temp_cdh, temp_eps, mode)
  alerts = []
  
  # Voltaje crítico
  if voltage < 6.8
    alerts << "CRÍTICO: Voltaje muy bajo (#{voltage.round(2)}V)"
  elsif voltage < 7.2
    alerts << "Voltaje bajo (#{voltage.round(2)}V)"
  end
  
  # Temperatura
  if temp_cdh > 55
    alerts << "CRÍTICO: Temperatura CDH muy alta (#{temp_cdh.round(1)}°C)"
  elsif temp_cdh > 50
    alerts << "Temperatura CDH elevada (#{temp_cdh.round(1)}°C)"
  end
  
  if temp_eps > 60
    alerts << "CRÍTICO: Temperatura EPS muy alta (#{temp_eps.round(1)}°C)"
  elsif temp_eps > 55
    alerts << "Temperatura EPS elevada (#{temp_eps.round(1)}°C)"
  end
  
  # Temperaturas bajas
  if temp_cdh < -15
    alerts << "Temperatura CDH muy baja (#{temp_cdh.round(1)}°C)"
  end
  
  return alerts
end

# Helper: Ejecutar secuencia AOS
def execute_aos_sequence(log_file)
  log_file.puts "\n[#{Time.now}] === SECUENCIA AOS ==="
  
  # NOOP para confirmar comunicación
  log_file.puts "[#{Time.now}] Enviando NOOP..."
  cmd("CHASQUI_II NOOPERATION")
  wait(2)
  
  # Solicitar parámetros
  log_file.puts "[#{Time.now}] Solicitando STATIC PARAMS..."
  cmd("CHASQUI_II ISSUEPACKET with PACKET StaticPar, STREAM DEBUG")
  wait(3)
  
  log_file.puts "[#{Time.now}] Solicitando DYNAMIC PARAMS..."
  cmd("CHASQUI_II ISSUEPACKET with PACKET DynamicPar, STREAM DEBUG")
  wait(3)
  
  # Sincronizar tiempo
  log_file.puts "[#{Time.now}] Sincronizando tiempo..."
  current_time = Time.now.to_i
  cmd("CHASQUI_II SETLINUXTIME with SECONDS #{current_time}")
  wait(2)
  
  log_file.puts "[#{Time.now}] === FIN SECUENCIA AOS ===\n"
  log_file.flush
  
  set_global_variable("PASS_COMMANDS_SENT", get_global_variable("PASS_COMMANDS_SENT") + 4)
  
  puts "[AUTO] Secuencia AOS completada"
end

# Helper: Descarga automática
def execute_auto_download(log_file)
  log_file.puts "\n[#{Time.now}] === DESCARGA AUTOMÁTICA ==="
  
  begin
    # Solicitar dynamic params para obtener punteros
    cmd("CHASQUI_II ISSUEPACKET with PACKET DynamicPar, STREAM DEBUG")
    wait(3)
    
    # Leer punteros
    write_ptr = tlm("CHASQUI_II DYNAMICPARS PKTWRITEPTR[0]")
    read_ptr = tlm("CHASQUI_II DYNAMICPARS PKTREADPTR[0]")
    available = write_ptr - read_ptr
    
    log_file.puts "[#{Time.now}] Beacons disponibles: #{available}"
    
    if available > 20
      # Descargar en bloque de 30
      download_count = [available, 30].min
      log_file.puts "[#{Time.now}] Descargando #{download_count} beacons..."
      
      cmd("CHASQUI_II PLAYBACK with PARTITION Beacon, READPOINTER #{read_ptr}, NPACKETS #{download_count}")
      
      puts "[AUTO] Descargando #{download_count} beacons..."
    else
      log_file.puts "[#{Time.now}] Pocos beacons disponibles (#{available})"
    end
    
  rescue => e
    log_file.puts "[#{Time.now}] ERROR en descarga: #{e.message}"
  end
  
  log_file.puts "[#{Time.now}] === FIN DESCARGA ===\n"
  log_file.flush
end

# Helper: Recuperación de emergencia
def execute_emergency_recovery(log_file)
  log_file.puts "\n[#{Time.now}] === RECUPERACIÓN DE EMERGENCIA ==="
  
  # Apagar payload
  log_file.puts "[#{Time.now}] Apagando payload..."
  cmd("CHASQUI_II TURNOFFPERIPHERAL with PERIPHERAL PL")
  wait(2)
  
  # Forzar modo SAFE
  log_file.puts "[#{Time.now}] Forzando modo SAFE..."
  cmd("CHASQUI_II SWITCHTOSAFE")
  wait(5)
  
  # Configurar perfil LOW_POWER
  log_file.puts "[#{Time.now}] Aplicando perfil LOW_POWER..."
  cmd("CHASQUI_II SETEPSREADINTERVAL with INTERVAL 60000")
  wait(1)
  cmd("CHASQUI_II SETBCNPACKETINTERVAL with INTERVAL 120000")
  wait(1)
  
  log_file.puts "[#{Time.now}] === FIN RECUPERACIÓN ===\n"
  log_file.flush
  
  puts "[AUTO] Recuperación de emergencia completada"
end

# Ejecución desde Script Runner
if __FILE__ == $0
  auto_cmd = ask("¿Habilitar comandos automáticos? (y/n):").downcase == 'y'
  auto_dl = ask("¿Habilitar descarga automática? (y/n):").downcase == 'y'
  
  result = monitor_pass_real_time(auto_commands: auto_cmd, auto_download: auto_dl)
  
  puts "\n✓ Monitoreo finalizado"
  puts "  Paquetes: #{result[:packets]}"
  puts "  Alertas: #{result[:alerts]}"
end
