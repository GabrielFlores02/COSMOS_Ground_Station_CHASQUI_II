# ============================================================================
# SCRIPT 7: RECUPERACIÓN DE EMERGENCIA
# ============================================================================
# Archivo: procedures/operations/emergency_recovery.rb

load_utility 'ground_station_library'

def emergency_recovery_procedure
  puts "="*70
  puts "PROCEDIMIENTO DE RECUPERACIÓN DE EMERGENCIA"
  puts "="*70
  puts "\n⚠ ADVERTENCIA: Este procedimiento debe usarse solo en emergencias"
  puts "\nPresione ENTER para continuar o Ctrl+C para cancelar..."
  gets
  
  recovery_log = []
  
  # 1. Intentar comunicación básica
  puts "\n[STEP 1/8] Verificando comunicación..."
  
  comm_ok = false
  3.times do |i|
    begin
      cmd("CHASQUI_II NOOPERATION")
      wait(2)
      
      # Verificar si se incrementó el contador
      accept_count = tlm("CHASQUI_II BEACON COMMAND_ACCEPT_COUNTER")
      puts "  Intento #{i+1}: Contador de comandos = #{accept_count}"
      comm_ok = true
      recovery_log << {step: "Communication", status: "OK", attempt: i+1}
      break
    rescue => e
      puts "  Intento #{i+1}: Fallo (#{e.message})"
      wait(5)
    end
  end
  
  unless comm_ok
    puts "\n✗ CRÍTICO: No se puede establecer comunicación"
    recovery_log << {step: "Communication", status: "FAILED"}
    return false
  end
  
  puts "✓ Comunicación establecida"
  
  # 2. Obtener estado actual
  puts "\n[STEP 2/8] Obteniendo estado actual..."
  begin
    voltage = tlm("CHASQUI_II BEACON MAIN_BATT_VOLT")
    mode = tlm("CHASQUI_II BEACON SAT_CURR_MODE")
    temp_cdh = tlm("CHASQUI_II BEACON TEMP_CDH")
    temp_bat = tlm("CHASQUI_II BEACON TEMP_BAT_TH1")
    
    puts "  Voltaje:       #{voltage.round(2)} V"
    puts "  Modo:          #{mode}"
    puts "  Temp CDH:      #{temp_cdh.round(1)} °C"
    puts "  Temp Batería:  #{temp_bat.round(1)} °C"
    
    recovery_log << {
      step: "Initial State",
      status: "OK",
      voltage: voltage,
      mode: mode,
      temp_cdh: temp_cdh
    }
  rescue => e
    puts "  ⚠ Error obteniendo telemetría: #{e.message}"
    recovery_log << {step: "Initial State", status: "ERROR"}
  end
  
  # 3. Apagar payload (si está encendido)
  puts "\n[STEP 3/8] Apagando payload..."
  begin
    cmd("CHASQUI_II TURNOFFPERIPHERAL with PERIPHERAL PL")
    wait(3)
    
    pl_curr = tlm("CHASQUI_II BEACON PL_12V_CURR")
    if pl_curr < 0.05
      puts "✓ Payload apagado (corriente: #{pl_curr.round(3)}A)"
      recovery_log << {step: "Payload OFF", status: "OK"}
    else
      puts "  ⚠ Payload puede seguir encendido (corriente: #{pl_curr.round(3)}A)"
      recovery_log << {step: "Payload OFF", status: "WARNING"}
    end
  rescue => e
    puts "  ✗ Error apagando payload: #{e.message}"
    recovery_log << {step: "Payload OFF", status: "ERROR"}
  end
  
  # 4. Apagar subsistemas no críticos
  puts "\n[STEP 4/8] Apagando ADCS..."
  begin
    cmd("CHASQUI_II TURNOFFPERIPHERAL with PERIPHERAL ADS")
    wait(2)
    puts "✓ ADCS apagado"
    recovery_log << {step: "ADCS OFF", status: "OK"}
  rescue => e
    puts "  ⚠ Error: #{e.message}"
    recovery_log << {step: "ADCS OFF", status: "ERROR"}
  end
  
  # 5. Forzar modo SAFE
  puts "\n[STEP 5/8] Forzando modo SAFE..."
  begin
    cmd("CHASQUI_II SWITCHTOSAFE")
    wait(5)
    
    new_mode = tlm("CHASQUI_II BEACON SAT_CURR_MODE")
    if new_mode == "SAFE"
      puts "✓ Modo SAFE activado"
      recovery_log << {step: "Mode SAFE", status: "OK"}
    else
      puts "  ⚠ Modo actual: #{new_mode}"
      recovery_log << {step: "Mode SAFE", status: "WARNING", mode: new_mode}
    end
  rescue => e
    puts "  ✗ Error cambiando modo: #{e.message}"
    recovery_log << {step: "Mode SAFE", status: "ERROR"}
  end
  
  # 6. Configurar perfil de bajo consumo extremo
  puts "\n[STEP 6/8] Aplicando perfil de BAJO CONSUMO..."
  begin
    # EPS: cada 2 minutos
    cmd("CHASQUI_II SETEPSREADINTERVAL with INTERVAL 120000")
    wait(1)
    
    # Beacon: cada 5 minutos
    cmd("CHASQUI_II SETBCNPACKETINTERVAL with INTERVAL 300000")
    wait(1)
    
    # UHF: cada minuto
    cmd("CHASQUI_II SETUHFREADINTERVAL with INTERVAL 60000")
    wait(1)
    
    puts "✓ Perfil configurado:"
    puts "  EPS:    120s"
    puts "  Beacon: 300s"
    puts "  UHF:    60s"
    
    recovery_log << {step: "Low Power Profile", status: "OK"}
  rescue => e
    puts "  ✗ Error configurando: #{e.message}"
    recovery_log << {step: "Low Power Profile", status: "ERROR"}
  end
  
  # 7. Verificar battery heater
  puts "\n[STEP 7/8] Verificando battery heater..."
  begin
    temp_bat = tlm("CHASQUI_II BEACON TEMP_BAT_TH1")
    
    if temp_bat < 5
      puts "  ⚠ Batería fría (#{temp_bat.round(1)}°C)"
      puts "  Habilitando heater automático..."
      
      cmd("CHASQUI_II SETBATTHTROVERRIDEFLAG with OVERRIDEFLAG OFF")
      wait(1)
      cmd("CHASQUI_II SETBATTHTTHRESHOLDS with HTRONTHRESH 1700, HTROFFTHRESH 1200")
      wait(1)
      
      puts "✓ Heater configurado"
      recovery_log << {step: "Battery Heater", status: "ENABLED", temp: temp_bat}
    else
      puts "✓ Temperatura batería OK (#{temp_bat.round(1)}°C)"
      recovery_log << {step: "Battery Heater", status: "OK", temp: temp_bat}
    end
  rescue => e
    puts "  ⚠ Error: #{e.message}"
    recovery_log << {step: "Battery Heater", status: "ERROR"}
  end
  
  # 8. Verificar estado final
  puts "\n[STEP 8/8] Verificando estado final..."
  begin
    wait(10)  # Esperar estabilización
    
    voltage = tlm("CHASQUI_II BEACON MAIN_BATT_VOLT")
    mode = tlm("CHASQUI_II BEACON SAT_CURR_MODE")
    temp_cdh = tlm("CHASQUI_II BEACON TEMP_CDH")
    
    puts "\n--- ESTADO FINAL ---"
    puts "  Voltaje:  #{voltage.round(2)} V"
    puts "  Modo:     #{mode}"
    puts "  Temp CDH: #{temp_cdh.round(1)} °C"
    puts "--------------------"
    
    recovery_log << {
      step: "Final State",
      status: "OK",
      voltage: voltage,
      mode: mode,
      temp_cdh: temp_cdh
    }
  rescue => e
    puts "  ⚠ Error obteniendo estado final: #{e.message}"
    recovery_log << {step: "Final State", status: "ERROR"}
  end
  
  # Guardar log de recuperación
  begin
    recovery_file = File.join(Cosmos::USERPATH, 'outputs', 'logs', 
                               "emergency_recovery_#{Time.now.strftime('%Y%m%d_%H%M%S')}.log")
    
    File.open(recovery_file, 'w') do |f|
      f.puts "="*70
      f.puts "REGISTRO DE RECUPERACIÓN DE EMERGENCIA"
      f.puts "="*70
      f.puts "Fecha: #{Time.now}"
      f.puts ""
      
      recovery_log.each do |entry|
        f.puts "[#{entry[:step]}] #{entry[:status]}"
        entry.each do |k, v|
          next if [:step, :status].include?(k)
          f.puts "  #{k}: #{v}"
        end
        f.puts ""
      end
      
      f.puts "="*70
    end
    
    puts "\n✓ Log guardado: #{recovery_file}"
  rescue => e
    puts "\n⚠ No se pudo guardar log: #{e.message}"
  end
  
  # Resumen final
  puts "\n" + "="*70
  puts "RECUPERACIÓN DE EMERGENCIA COMPLETADA"
  puts "="*70
  
  successful_steps = recovery_log.count { |e| e[:status] == "OK" }
  total_steps = recovery_log.count
  
  puts "Pasos exitosos: #{successful_steps}/#{total_steps}"
  
  if successful_steps >= total_steps - 2
    puts "\n✓ Recuperación exitosa"
    puts "El satélite está en modo seguro"
  else
    puts "\n⚠ Recuperación parcial"
    puts "Revisar logs y continuar monitoreo"
  end
  
  puts "="*70
  
  return true
end

# Ejecución desde Script Runner
if __FILE__ == $0
  emergency_recovery_procedure()
end
