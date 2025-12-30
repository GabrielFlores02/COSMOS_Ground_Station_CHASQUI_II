# ============================================================================
# SCRIPT 5: OPERACIÓN CIENTÍFICA (Payload)
# ============================================================================
# Archivo: procedures/operations/science_operation.rb

load_utility 'ground_station_library'

def science_payload_operation(duration_min: 10, interval_ms: 30000)
  puts "="*70
  puts "OPERACIÓN CIENTÍFICA - PAYLOAD"
  puts "="*70
  puts "Duración: #{duration_min} minutos"
  puts "Intervalo: #{interval_ms}ms (#{interval_ms/1000}s)"
  puts "="*70
  
  # Verificar salud antes de comenzar
  puts "\n[STEP 1/7] Verificando salud del satélite..."
  
  voltage = tlm("CHASQUI_II BEACON MAIN_BATT_VOLT")
  temp_cdh = tlm("CHASQUI_II BEACON TEMP_CDH")
  mode = tlm("CHASQUI_II BEACON SAT_CURR_MODE")
  
  puts "  Voltaje:     #{voltage.round(2)} V"
  puts "  Temperatura: #{temp_cdh.round(1)} °C"
  puts "  Modo:        #{mode}"
  
  # Verificar condiciones mínimas
  if voltage < 7.5
    puts "\n✗ ABORTADO: Voltaje insuficiente (#{voltage}V < 7.5V)"
    return false
  end
  
  if temp_cdh > 45
    puts "\n✗ ABORTADO: Temperatura muy alta (#{temp_cdh}°C > 45°C)"
    return false
  end
  
  puts "✓ Condiciones adecuadas para operación"
  
  # Cambiar a modo NOMINAL si es necesario
  if mode != "NOMINAL"
    puts "\n[STEP 2/7] Cambiando a modo NOMINAL..."
    cmd("CHASQUI_II SWITCHTONOMINAL")
    wait(5)
    
    new_mode = tlm("CHASQUI_II BEACON SAT_CURR_MODE")
    if new_mode != "NOMINAL"
      puts "✗ No se pudo cambiar a NOMINAL"
      return false
    end
    puts "✓ Modo NOMINAL activado"
  else
    puts "\n[STEP 2/7] Ya está en modo NOMINAL"
  end
  
  # Configurar perfil científico
  puts "\n[STEP 3/7] Configurando perfil científico..."
  cmd("CHASQUI_II SETEPSREADINTERVAL with INTERVAL 10000")
  wait(1)
  cmd("CHASQUI_II SETUHFREADINTERVAL with INTERVAL 5000")
  wait(1)
  cmd("CHASQUI_II SETBCNPACKETINTERVAL with INTERVAL 60000")
  wait(1)
  cmd("CHASQUI_II SETPLINTERVAL with INTERVAL #{interval_ms}")
  wait(1)
  puts "✓ Perfil configurado"
  
  # Encender payload
  puts "\n[STEP 4/7] Encendiendo payload..."
  cmd("CHASQUI_II TURNONPERIPHERAL with PERIPHERAL PL")
  wait(5)
  
  # Verificar corriente de payload
  pl_curr = tlm("CHASQUI_II BEACON PL_12V_CURR")
  if pl_curr > 0.05
    puts "✓ Payload encendido (corriente: #{pl_curr.round(3)}A)"
  else
    puts "⚠ Advertencia: No se detecta corriente de payload"
  end
  
  # Operación del payload
  puts "\n[STEP 5/7] Operando payload durante #{duration_min} minutos..."
  
  start_time = Time.now
  end_time = start_time + (duration_min * 60)
  samples_collected = 0
  
  while Time.now < end_time
    remaining = ((end_time - Time.now) / 60.0).round(1)
    
    # Verificar salud cada minuto
    voltage = tlm("CHASQUI_II BEACON MAIN_BATT_VOLT")
    temp_cdh = tlm("CHASQUI_II BEACON TEMP_CDH")
    pl_curr = tlm("CHASQUI_II BEACON PL_12V_CURR")
    
    print "\r[SCIENCE] T-#{remaining}min | V:#{voltage.round(2)}V T:#{temp_cdh.round(1)}°C I_PL:#{pl_curr.round(3)}A"
    STDOUT.flush
    
    # Verificar condiciones de emergencia
    if voltage < 7.2
      puts "\n⚠ ALERTA: Voltaje bajo - Abortando operación"
      break
    end
    
    if temp_cdh > 50
      puts "\n⚠ ALERTA: Temperatura alta - Abortando operación"
      break
    end
    
    samples_collected += 1
    wait(60)  # Verificar cada minuto
  end
  
  puts "\n✓ Operación completada"
  
  # Apagar payload
  puts "\n[STEP 6/7] Apagando payload..."
  cmd("CHASQUI_II TURNOFFPERIPHERAL with PERIPHERAL PL")
  wait(3)
  puts "✓ Payload apagado"
  
  # Solicitar datos generados
  puts "\n[STEP 7/7] Solicitando datos generados..."
  cmd("CHASQUI_II ISSUEPACKET with PACKET PL, STREAM DEBUG")
  wait(3)
  puts "✓ Datos solicitados"
  
  # Resumen
  puts "\n" + "="*70
  puts "✓ OPERACIÓN CIENTÍFICA COMPLETADA"
  puts "="*70
  puts "Duración real:    #{((Time.now - start_time)/60.0).round(1)} min"
  puts "Muestras:         #{samples_collected}"
  puts "="*70
  
  return true
end

# Ejecución desde Script Runner
if __FILE__ == $0
  duration = ask("Duración de operación (minutos):").to_i
  interval = ask("Intervalo de muestreo (ms):").to_i
  
  science_payload_operation(duration_min: duration, interval_ms: interval)
end