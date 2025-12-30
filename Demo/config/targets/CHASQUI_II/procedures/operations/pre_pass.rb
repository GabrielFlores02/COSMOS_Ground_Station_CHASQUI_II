# ============================================================================
# SCRIPT 1: PRE-PASE (Verificación y Preparación)
# ============================================================================
# Archivo: procedures/operations/pre_pass.rb

load_utility 'ground_station_library'

def pre_pass_checks(pass_start_time, pass_duration, max_elevation)
  puts "="*70
  puts "VERIFICACIÓN PRE-PASE - CHASQUI II"
  puts "="*70
  puts "Inicio programado: #{pass_start_time.strftime('%Y-%m-%d %H:%M:%S')}"
  puts "Duración estimada: #{pass_duration} minutos"
  puts "Elevación máxima: #{max_elevation}°"
  puts "="*70
  
  all_ok = true
  checks_log = []
  
  # 1. Verificar interfaz GNU Radio
  puts "\n[CHECK 1/10] Verificando GNU Radio..."
  begin
    interface_names = get_interface_names()
    
    if interface_names.include?("GNURADIO_INTERFACE")
      interface_info = get_interface_info("GNURADIO_INTERFACE")
      
      if interface_info['state'] == 'CONNECTED'
        puts "✓ GNU Radio: CONECTADO"
        checks_log << {check: "GNU Radio", status: "OK"}
      else
        puts "✗ GNU Radio: DESCONECTADO - Intentando reconectar..."
        connect_interface("GNURADIO_INTERFACE")
        wait(5)
        
        # Verificar nuevamente
        interface_info = get_interface_info("GNURADIO_INTERFACE")
        if interface_info['state'] == 'CONNECTED'
          puts "✓ GNU Radio: Reconectado exitosamente"
          checks_log << {check: "GNU Radio", status: "RECONNECTED"}
        else
          puts "✗ GNU Radio: NO SE PUDO RECONECTAR"
          checks_log << {check: "GNU Radio", status: "FAILED"}
          all_ok = false
        end
      end
    else
      puts "✗ ERROR CRÍTICO: Interfaz GNU Radio no configurada"
      checks_log << {check: "GNU Radio", status: "NOT_CONFIGURED"}
      all_ok = false
    end
  rescue => e
    puts "✗ ERROR verificando GNU Radio: #{e.message}"
    checks_log << {check: "GNU Radio", status: "ERROR", msg: e.message}
    all_ok = false
  end
  
  # 2. Verificar rotctld (Hamlib para rotor)
  puts "\n[CHECK 2/10] Verificando rotctld (Hamlib)..."
  begin
    require 'socket'
    TCPSocket.new('localhost', 4533).close
    puts "✓ rotctld: Puerto 4533 disponible"
    checks_log << {check: "rotctld", status: "OK"}
  rescue Errno::ECONNREFUSED
    puts "✗ rotctld: No está ejecutándose"
    puts "  Iniciar con: rotctld -m 603 -r /dev/ttyUSB0"
    checks_log << {check: "rotctld", status: "NOT_RUNNING"}
    all_ok = false
  rescue => e
    puts "⚠ rotctld: Error verificando (#{e.message})"
    checks_log << {check: "rotctld", status: "WARNING"}
  end
  
  # 3. Verificar gpredict
  puts "\n[CHECK 3/10] Verificando integración Gpredict..."
  begin
    # Verificar si el puerto de gpredict está disponible
    TCPSocket.new('localhost', 4532).close
    puts "✓ Gpredict: Puerto 4532 disponible"
    checks_log << {check: "Gpredict", status: "OK"}
  rescue Errno::ECONNREFUSED
    puts "⚠ Gpredict: No detectado (opcional)"
    checks_log << {check: "Gpredict", status: "OPTIONAL"}
  rescue => e
    puts "⚠ Gpredict: #{e.message}"
  end
  
  # 4. Verificar espacio en disco
  puts "\n[CHECK 4/10] Verificando espacio en disco..."
  begin
    logs_path = File.join(Cosmos::USERPATH, 'outputs', 'logs')
    
    if RUBY_PLATFORM =~ /linux|darwin/
      disk_output = `df -h #{logs_path} 2>&1`
      disk_line = disk_output.split("\n").last
      available = disk_line.split[3]
      
      # Extraer número
      if available =~ /(\d+\.?\d*)G/
        space_gb = $1.to_f
        if space_gb >= 1.0
          puts "✓ Espacio disponible: #{available} (OK)"
          checks_log << {check: "Disk Space", status: "OK", value: available}
        else
          puts "⚠ ADVERTENCIA: Espacio bajo (#{available})"
          checks_log << {check: "Disk Space", status: "LOW", value: available}
        end
      else
        puts "✓ Espacio disponible: #{available}"
        checks_log << {check: "Disk Space", status: "OK", value: available}
      end
    else
      puts "⚠ Verificación de disco no disponible en Windows"
      checks_log << {check: "Disk Space", status: "SKIPPED"}
    end
  rescue => e
    puts "⚠ No se pudo verificar espacio: #{e.message}"
    checks_log << {check: "Disk Space", status: "ERROR"}
  end
  
  # 5. Verificar logging
  puts "\n[CHECK 5/10] Verificando sistema de logging..."
  begin
    unless cmd_log_running?()
      start_cmd_log()
      puts "✓ Command logging: INICIADO"
    else
      puts "✓ Command logging: YA ACTIVO"
    end
    
    unless tlm_log_running?()
      start_tlm_log()
      puts "✓ Telemetry logging: INICIADO"
    else
      puts "✓ Telemetry logging: YA ACTIVO"
    end
    
    checks_log << {check: "Logging", status: "OK"}
  rescue => e
    puts "✗ Error en logging: #{e.message}"
    checks_log << {check: "Logging", status: "ERROR"}
    all_ok = false
  end
  
  # 6. Verificar última telemetría conocida
  puts "\n[CHECK 6/10] Verificando última telemetría..."
  begin
    voltage = tlm("CHASQUI_II BEACON MAIN_BATT_VOLT")
    mode = tlm("CHASQUI_II BEACON SAT_CURR_MODE")
    temp = tlm("CHASQUI_II BEACON TEMP_CDH")
    boot_count = tlm("CHASQUI_II BEACON BOOT_COUNTER")
    
    puts "\n--- ÚLTIMO ESTADO CONOCIDO ---"
    puts "  Voltaje:     #{voltage.round(2)} V"
    puts "  Modo:        #{mode}"
    puts "  Temperatura: #{temp.round(1)} °C"
    puts "  Boot count:  #{boot_count}"
    puts "-------------------------------"
    
    # Verificar condiciones críticas
    warnings = []
    if voltage < 7.0
      warnings << "Voltaje crítico: #{voltage}V"
    elsif voltage < 7.5
      warnings << "Voltaje bajo: #{voltage}V"
    end
    
    if temp > 50 || temp < -15
      warnings << "Temperatura fuera de rango: #{temp}°C"
    end
    
    if warnings.any?
      puts "\n⚠ ADVERTENCIAS:"
      warnings.each { |w| puts "  - #{w}" }
    end
    
    checks_log << {check: "Last Telemetry", status: "OK", voltage: voltage, mode: mode}
    
  rescue => e
    puts "⚠ No hay telemetría reciente disponible"
    puts "  (Normal si no ha habido contacto reciente)"
    checks_log << {check: "Last Telemetry", status: "UNAVAILABLE"}
  end
  
  # 7. Crear estructura de directorios
  puts "\n[CHECK 7/10] Preparando estructura de archivos..."
  begin
    timestamp = pass_start_time.strftime("%Y%m%d_%H%M%S")
    passes_base = File.join(Cosmos::USERPATH, 'outputs', 'passes')
    pass_dir = File.join(passes_base, "pass_#{timestamp}")
    
    Dir.mkdir(passes_base) unless Dir.exist?(passes_base)
    Dir.mkdir(pass_dir) unless Dir.exist?(pass_dir)
    
    # Crear subdirectorios
    ['tlm', 'logs', 'reports'].each do |subdir|
      subdir_path = File.join(pass_dir, subdir)
      Dir.mkdir(subdir_path) unless Dir.exist?(subdir_path)
    end
    
    set_global_variable("CURRENT_PASS_DIR", pass_dir)
    set_global_variable("CURRENT_PASS_TIMESTAMP", timestamp)
    
    puts "✓ Directorio creado: #{pass_dir}"
    checks_log << {check: "Directory Structure", status: "OK", path: pass_dir}
    
  rescue => e
    puts "✗ Error creando directorios: #{e.message}"
    checks_log << {check: "Directory Structure", status: "ERROR"}
    all_ok = false
  end
  
  # 8. Inicializar variables globales del pase
  puts "\n[CHECK 8/10] Inicializando variables de sesión..."
  begin
    set_global_variable("PASS_PACKET_COUNT", 0)
    set_global_variable("PASS_START_TIME", pass_start_time)
    set_global_variable("PASS_DURATION", pass_duration)
    set_global_variable("PASS_MAX_ELEVATION", max_elevation)
    set_global_variable("PASS_AOS_TIME", nil)
    set_global_variable("PASS_LOS_TIME", nil)
    set_global_variable("PASS_COMMANDS_SENT", 0)
    set_global_variable("PASS_COMMANDS_SUCCESS", 0)
    set_global_variable("PASS_HEALTH_ALERTS", [])
    
    puts "✓ Variables de sesión inicializadas"
    checks_log << {check: "Session Variables", status: "OK"}
  rescue => e
    puts "✗ Error inicializando variables: #{e.message}"
    checks_log << {check: "Session Variables", status: "ERROR"}
    all_ok = false
  end
  
  # 9. Crear archivo de información del pase
  puts "\n[CHECK 9/10] Creando archivo de información..."
  begin
    pass_dir = get_global_variable("CURRENT_PASS_DIR")
    info_file = File.join(pass_dir, "pass_info.txt")
    
    File.open(info_file, 'w') do |f|
      f.puts "="*70
      f.puts "INFORMACIÓN DEL PASE - CHASQUI II"
      f.puts "="*70
      f.puts ""
      f.puts "PARÁMETROS DEL PASE:"
      f.puts "  Inicio programado:  #{pass_start_time.strftime('%Y-%m-%d %H:%M:%S UTC')}"
      f.puts "  Duración estimada:  #{pass_duration} minutos"
      f.puts "  Elevación máxima:   #{max_elevation}°"
      f.puts ""
      f.puts "SISTEMA:"
      f.puts "  COSMOS Version:     #{Cosmos::VERSION}"
      f.puts "  Timestamp archivo:  #{get_global_variable('CURRENT_PASS_TIMESTAMP')}"
      f.puts "  Directorio:         #{pass_dir}"
      f.puts ""
      f.puts "="*70
      f.puts ""
      f.puts "VERIFICACIONES PRE-PASE:"
      checks_log.each do |check|
        f.puts "  [#{check[:status].ljust(15)}] #{check[:check]}"
      end
      f.puts ""
      f.puts "="*70
    end
    
    puts "✓ Archivo de información creado"
    checks_log << {check: "Info File", status: "OK"}
    
  rescue => e
    puts "⚠ No se pudo crear archivo de información: #{e.message}"
    checks_log << {check: "Info File", status: "WARNING"}
  end
  
  # 10. Verificar permisos de escritura
  puts "\n[CHECK 10/10] Verificando permisos de escritura..."
  begin
    pass_dir = get_global_variable("CURRENT_PASS_DIR")
    test_file = File.join(pass_dir, '.write_test')
    
    File.open(test_file, 'w') { |f| f.puts "test" }
    File.delete(test_file)
    
    puts "✓ Permisos de escritura: OK"
    checks_log << {check: "Write Permissions", status: "OK"}
  rescue => e
    puts "✗ Error de permisos: #{e.message}"
    checks_log << {check: "Write Permissions", status: "ERROR"}
    all_ok = false
  end
  
  # Resumen final
  puts "\n" + "="*70
  if all_ok
    puts "✓✓✓ VERIFICACIÓN PRE-PASE COMPLETADA EXITOSAMENTE ✓✓✓"
    puts "Sistema LISTO para contacto"
  else
    puts "⚠⚠⚠ VERIFICACIÓN COMPLETADA CON ERRORES ⚠⚠⚠"
    puts "Revisar problemas críticos antes del pase"
  end
  puts "="*70
  
  return all_ok
end

# Ejecución directa desde Script Runner
if __FILE__ == $0
  # Solicitar parámetros al usuario
  pass_start = ask("Tiempo de inicio del pase (ej: 2024-01-15 14:30:00):")
  duration = ask("Duración del pase en minutos:").to_i
  max_el = ask("Elevación máxima en grados:").to_i
  
  # Parsear tiempo
  pass_time = Time.parse(pass_start)
  
  # Ejecutar verificación
  result = pre_pass_checks(pass_time, duration, max_el)
  
  if result
    puts "\n✓ Puede proceder con el pase"
  else
    puts "\n✗ Corrija los problemas antes de continuar"
  end
end
