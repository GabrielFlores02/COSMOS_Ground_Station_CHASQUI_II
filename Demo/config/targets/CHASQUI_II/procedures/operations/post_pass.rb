# ============================================================================
# SCRIPT 3: POST-PASE (Análisis y Reportes)
# ============================================================================
# Archivo: procedures/operations/post_pass.rb

load_utility 'ground_station_library'
require 'csv'

def post_pass_analysis
  puts "="*70
  puts "ANÁLISIS POST-PASE"
  puts "="*70
  
  # Obtener datos del pase
  pass_dir = get_global_variable("CURRENT_PASS_DIR")
  pass_timestamp = get_global_variable("CURRENT_PASS_TIMESTAMP")
  aos_time = get_global_variable("PASS_AOS_TIME")
  los_time = get_global_variable("PASS_LOS_TIME")
  packet_count = get_global_variable("PASS_PACKET_COUNT") || 0
  health_alerts = get_global_variable("PASS_HEALTH_ALERTS") || []
  
  unless pass_dir && Dir.exist?(pass_dir)
    puts "✗ ERROR: No hay información de pase disponible"
    return false
  end
  
  puts "\nDirectorio: #{pass_dir}"
  puts "\n[STEP 1/6] Analizando datos del pase..."
  
  # Calcular duración real
  if aos_time && los_time
    duration_sec = (los_time - aos_time).round(0)
    duration_min = (duration_sec / 60.0).round(1)
    
    puts "  AOS:      #{aos_time.strftime('%H:%M:%S')}"
    puts "  LOS:      #{los_time.strftime('%H:%M:%S')}"
    puts "  Duración: #{duration_min} minutos (#{duration_sec}s)"
  else
    puts "  ⚠ No hay datos completos de AOS/LOS"
    duration_min = 0
  end
  
  puts "  Paquetes: #{packet_count}"
  puts "  Alertas:  #{health_alerts.count}"
  
  # Analizar health log
  puts "\n[STEP 2/6] Analizando telemetría de salud..."
  health_log_file = File.join(pass_dir, 'logs', 'health.log')
  
  health_stats = {
    voltage_min: 999,
    voltage_max: 0,
    voltage_avg: 0,
    temp_cdh_min: 999,
    temp_cdh_max: -999,
    temp_cdh_avg: 0,
    samples: 0
  }
  
  if File.exist?(health_log_file)
    voltage_sum = 0
    temp_sum = 0
    
    File.readlines(health_log_file).each do |line|
      next if line.strip.empty?
      
      parts = line.split(',')
      next if parts.length < 7
      
      begin
        voltage = parts[1].to_f
        temp_cdh = parts[3].to_f
        
        health_stats[:voltage_min] = [health_stats[:voltage_min], voltage].min
        health_stats[:voltage_max] = [health_stats[:voltage_max], voltage].max
        voltage_sum += voltage
        
        health_stats[:temp_cdh_min] = [health_stats[:temp_cdh_min], temp_cdh].min
        health_stats[:temp_cdh_max] = [health_stats[:temp_cdh_max], temp_cdh].max
        temp_sum += temp_cdh
        
        health_stats[:samples] += 1
      rescue
        next
      end
    end
    
    if health_stats[:samples] > 0
      health_stats[:voltage_avg] = (voltage_sum / health_stats[:samples]).round(2)
      health_stats[:temp_cdh_avg] = (temp_sum / health_stats[:samples]).round(1)
      
      puts "  Muestras de telemetría: #{health_stats[:samples]}"
      puts "  Voltaje:"
      puts "    Mínimo:   #{health_stats[:voltage_min].round(2)} V"
      puts "    Máximo:   #{health_stats[:voltage_max].round(2)} V"
      puts "    Promedio: #{health_stats[:voltage_avg]} V"
      puts "  Temperatura CDH:"
      puts "    Mínima:   #{health_stats[:temp_cdh_min].round(1)} °C"
      puts "    Máxima:   #{health_stats[:temp_cdh_max].round(1)} °C"
      puts "    Promedio: #{health_stats[:temp_cdh_avg]} °C"
    else
      puts "  ⚠ No se encontraron datos de telemetría"
    end
  else
    puts "  ⚠ Archivo de health log no encontrado"
  end
  
  # Analizar comandos
  puts "\n[STEP 3/6] Analizando comandos enviados..."
  commands_log_file = File.join(pass_dir, 'logs', 'commands.log')
  
  commands_sent = 0
  if File.exist?(commands_log_file)
    commands_sent = File.readlines(commands_log_file).count { |l| l.include?("Enviando") }
    puts "  Comandos enviados: #{commands_sent}"
  else
    puts "  ⚠ Log de comandos no encontrado"
  end
  
  # Copiar logs de COSMOS
  puts "\n[STEP 4/6] Copiando logs de COSMOS..."
  begin
    cosmos_logs_dir = File.join(Cosmos::USERPATH, 'outputs', 'logs')
    pass_logs_dir = File.join(pass_dir, 'tlm')
    
    # Buscar logs del día
    date_str = pass_timestamp[0..7]  # YYYYMMDD
    
    Dir.glob(File.join(cosmos_logs_dir, "**/*#{date_str}*.bin")).each do |log_file|
      if File.mtime(log_file) >= (aos_time || Time.now - 3600)
        dest = File.join(pass_logs_dir, File.basename(log_file))
        FileUtils.cp(log_file, dest)
        puts "  ✓ Copiado: #{File.basename(log_file)}"
      end
    end
  rescue => e
    puts "  ⚠ Error copiando logs: #{e.message}"
  end
  
  # Generar reporte final
  puts "\n[STEP 5/6] Generando reporte final..."
  report_file = File.join(pass_dir, 'reports', 'pass_report.txt')
  
  File.open(report_file, 'w') do |f|
    f.puts "="*70
    f.puts "REPORTE DE PASE - CHASQUI II"
    f.puts "="*70
    f.puts ""
    f.puts "INFORMACIÓN GENERAL"
    f.puts "-"*70
    f.puts "Timestamp:            #{pass_timestamp}"
    f.puts "Fecha y hora:         #{(aos_time || Time.now).strftime('%Y-%m-%d %H:%M:%S UTC')}"
    f.puts ""
    
    if aos_time && los_time
      f.puts "TIEMPOS DEL PASE"
      f.puts "-"*70
      f.puts "AOS:                  #{aos_time.strftime('%H:%M:%S')}"
      f.puts "LOS:                  #{los_time.strftime('%H:%M:%S')}"
      f.puts "Duración real:        #{duration_min} minutos"
      f.puts ""
    end
    
    f.puts "DATOS RECIBIDOS"
    f.puts "-"*70
    f.puts "Paquetes recibidos:   #{packet_count}"
    f.puts "Muestras de TLM:      #{health_stats[:samples]}"
    f.puts "Comandos enviados:    #{commands_sent}"
    f.puts ""
    
    if health_stats[:samples] > 0
      f.puts "TELEMETRÍA DE SALUD"
      f.puts "-"*70
      f.puts "Voltaje batería:"
      f.puts "  Mínimo:             #{health_stats[:voltage_min].round(2)} V"
      f.puts "  Máximo:             #{health_stats[:voltage_max].round(2)} V"
      f.puts "  Promedio:           #{health_stats[:voltage_avg]} V"
      f.puts ""
      f.puts "Temperatura CDH:"
      f.puts "  Mínima:             #{health_stats[:temp_cdh_min].round(1)} °C"
      f.puts "  Máxima:             #{health_stats[:temp_cdh_max].round(1)} °C"
      f.puts "  Promedio:           #{health_stats[:temp_cdh_avg]} °C"
      f.puts ""
    end
    
    if health_alerts.any?
      f.puts "ALERTAS Y EVENTOS"
      f.puts "-"*70
      f.puts "Total de alertas:     #{health_alerts.count}"
      f.puts ""
      health_alerts.each_with_index do |alert, i|
        f.puts "#{i+1}. [#{alert[:time].strftime('%H:%M:%S')}] #{alert[:alert]}"
      end
      f.puts ""
    end
    
    f.puts "ARCHIVOS GENERADOS"
    f.puts "-"*70
    f.puts "Logs:"
    f.puts "  - monitor.log        Eventos del pase"
    f.puts "  - health.log         Telemetría CSV"
    f.puts "  - commands.log       Comandos enviados"
    f.puts "Telemetría:"
    f.puts "  - tlm/*.bin          Logs binarios COSMOS"
    f.puts "Reportes:"
    f.puts "  - pass_report.txt    Este archivo"
    f.puts ""
    f.puts "="*70
  end
  
  puts "  ✓ Reporte generado: pass_report.txt"
  
  # Generar CSV resumen para análisis posterior
  puts "\n[STEP 6/6] Generando CSV de resumen..."
  summary_csv = File.join(Cosmos::USERPATH, 'outputs', 'passes', 'passes_summary.csv')
  
  # Crear header si no existe
  unless File.exist?(summary_csv)
    CSV.open(summary_csv, 'w') do |csv|
      csv << ['Timestamp', 'Date', 'AOS', 'LOS', 'Duration_min', 'Packets', 'Alerts', 
              'V_min', 'V_max', 'V_avg', 'T_min', 'T_max', 'T_avg', 'Commands']
    end
  end
  
  # Añadir datos del pase
  CSV.open(summary_csv, 'a') do |csv|
    csv << [
      pass_timestamp,
      (aos_time || Time.now).strftime('%Y-%m-%d'),
      aos_time&.strftime('%H:%M:%S'),
      los_time&.strftime('%H:%M:%S'),
      duration_min,
      packet_count,
      health_alerts.count,
      health_stats[:voltage_min] == 999 ? nil : health_stats[:voltage_min].round(2),
      health_stats[:voltage_max] == 0 ? nil : health_stats[:voltage_max].round(2),
      health_stats[:voltage_avg],
      health_stats[:temp_cdh_min] == 999 ? nil : health_stats[:temp_cdh_min].round(1),
      health_stats[:temp_cdh_max] == -999 ? nil : health_stats[:temp_cdh_max].round(1),
      health_stats[:temp_cdh_avg],
      commands_sent
    ]
  end
  
  puts "  ✓ CSV actualizado: passes_summary.csv"
  
  # Resumen final
  puts "\n" + "="*70
  puts "✓ ANÁLISIS POST-PASE COMPLETADO"
  puts "="*70
  puts "Directorio:  #{pass_dir}"
  puts "Reporte:     #{report_file}"
  puts "="*70
  
  # Limpiar variables globales
  set_global_variable("CURRENT_PASS_DIR", nil)
  set_global_variable("PASS_AOS_TIME", nil)
  set_global_variable("PASS_LOS_TIME", nil)
  
  return true
end

# Ejecución desde Script Runner
if __FILE__ == $0
  post_pass_analysis()
end