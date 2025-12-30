# ============================================
# COMMAND LIBRARY - CHASQUI_II
# Biblioteca de comandos específicos y secuencias
# ============================================

require 'cosmos'
require 'cosmos/script'

# ============================================
# FUNCIONES DE UTILIDAD
# ============================================

def send_noop_command
  """Enviar comando No-Operation para verificar comunicación"""
  puts "Enviando NOOP..."
  cmd("CHASQUI_II NOOPERATION")
  wait(1)
  
  # Verificar que el contador de comandos aceptados incrementó
  before = tlm("CHASQUI_II BEACON COMMAND_ACCEPT_COUNTER")
  wait(5)
  after = tlm("CHASQUI_II BEACON COMMAND_ACCEPT_COUNTER")
  
  if after > before
    puts "✓ Comando NOOP aceptado"
    return true
  else
    puts "✗ Comando NOOP no fue aceptado"
    return false
  end
end

def set_linux_time
  """Sincronizar tiempo del satélite con tiempo terrestre"""
  current_time = Time.now.to_i
  
  puts "Configurando tiempo Linux en satélite..."
  puts "Tiempo actual: #{Time.now}"
  puts "Unix timestamp: #{current_time}"
  
  cmd("CHASQUI_II SETLINUXTIME with SECONDS #{current_time}")
  wait(2)
  
  puts "✓ Comando de sincronización enviado"
end

# ============================================
# FUNCIONES DE STREAMING DE TELEMETRÍA
# ============================================

def enable_beacon_stream_uhf
  """Habilitar stream de beacon por UHF"""
  puts "Habilitando stream de beacon por UHF..."
  
  cmd("CHASQUI_II STREAMPACKET with PACKET BEACON, STREAM UHF")
  wait(1)
  
  puts "✓ Stream de beacon habilitado"
end

def disable_all_streams
  """Deshabilitar todos los streams"""
  puts "Deshabilitando todos los streams..."
  
  cmd("CHASQUI_II STREAMPACKET with PACKET BEACON, STREAM DISABLE")
  wait(1)
  
  puts "✓ Todos los streams deshabilitados"
end

def enable_debug_stream
  """Habilitar stream de debug"""
  puts "Habilitando stream de debug..."
  
  cmd("CHASQUI_II STREAMPACKET with PACKET BEACON, STREAM DEBUG")
  wait(1)
  
  puts "✓ Stream de debug habilitado"
end

# ============================================
# FUNCIONES DE GESTIÓN DE PERIFÉRICOS
# ============================================

def power_cycle_payload
  """Ciclo de potencia del payload"""
  puts "Ejecutando ciclo de potencia del payload..."
  
  # Apagar payload
  cmd("CHASQUI_II TURNOFFPERIPHERAL with PERIPHERAL PL")
  wait(5)
  puts "  Payload apagado"
  
  # Encender payload
  cmd("CHASQUI_II TURNONPERIPHERAL with PERIPHERAL PL")
  wait(2)
  puts "  Payload encendido"
  
  puts "✓ Ciclo de potencia completado"
end

def turn_on_battery_heater
  """Encender calentador de batería"""
  puts "Encendiendo calentador de batería..."
  
  cmd("CHASQUI_II TURNONPERIPHERAL with PERIPHERAL BATT_HTR")
  wait(1)
  
  puts "✓ Calentador encendido"
end

def turn_off_battery_heater
  """Apagar calentador de batería"""
  puts "Apagando calentador de batería..."
  
  cmd("CHASQUI_II TURNOFFPERIPHERAL with PERIPHERAL BATT_HTR")
  wait(1)
  
  puts "✓ Calentador apagado"
end

# ============================================
# FUNCIONES DE CONFIGURACIÓN DE INTERVALOS
# ============================================

def configure_nominal_intervals
  """Configurar intervalos para modo nominal"""
  puts "Configurando intervalos para modo nominal..."
  
  # EPS cada 10 segundos
  cmd("CHASQUI_II SETEPSREADINTERVAL with INTERVAL 10000")
  wait(1)
  
  # UHF cada 5 segundos
  cmd("CHASQUI_II SETUHFREADINTERVAL with INTERVAL 5000")
  wait(1)
  
  # Beacon cada 30 segundos
  cmd("CHASQUI_II SETBCNPACKETINTERVAL with INTERVAL 30000")
  wait(1)
  
  # Payload cada 60 segundos
  cmd("CHASQUI_II SETPLINTERVAL with INTERVAL 60000")
  wait(1)
  
  puts "✓ Intervalos nominales configurados"
end

def configure_safe_mode_intervals
  """Configurar intervalos para modo seguro (más conservador)"""
  puts "Configurando intervalos para modo seguro..."
  
  # EPS cada 30 segundos
  cmd("CHASQUI_II SETEPSREADINTERVAL with INTERVAL 30000")
  wait(1)
  
  # UHF cada 15 segundos
  cmd("CHASQUI_II SETUHFREADINTERVAL with INTERVAL 15000")
  wait(1)
  
  # Beacon cada 60 segundos
  cmd("CHASQUI_II SETBCNPACKETINTERVAL with INTERVAL 60000")
  wait(1)
  
  puts "✓ Intervalos de modo seguro configurados"
end

# ============================================
# FUNCIONES DE GESTIÓN DE MODOS
# ============================================

def transition_to_nominal
  """Transición de Safe a Nominal con verificaciones"""
  puts "Iniciando transición Safe → Nominal..."
  
  # Verificar modo actual
  current_mode = tlm("CHASQUI_II BEACON SAT_CURR_MODE")
  puts "Modo actual: #{current_mode}"
  
  if current_mode != "SAFE"
    puts "⚠ Satélite no está en modo SAFE"
    return false
  end
  
  # Verificar voltaje
  voltage = tlm("CHASQUI_II BEACON MAIN_BATT_VOLT")
  puts "Voltaje batería: #{voltage}V"
  
  if voltage < 7.5
    puts "✗ Voltaje insuficiente (< 7.5V)"
    return false
  end
  
  # Verificar temperatura
  temp = tlm("CHASQUI_II BEACON TEMP_CDH")
  puts "Temperatura CDH: #{temp}°C"
  
  if temp < -10 || temp > 50
    puts "✗ Temperatura fuera de rango"
    return false
  end
  
  # Enviar comando de cambio de modo
  puts "Enviando comando Switch to Nominal..."
  cmd("CHASQUI_II SWITCHTONOMINAL")
  wait(5)
  
  # Verificar cambio
  new_mode = tlm("CHASQUI_II BEACON SAT_CURR_MODE")
  
  if new_mode == "NOMINAL"
    puts "✓ Transición exitosa a modo NOMINAL"
    return true
  else
    puts "✗ Transición falló. Modo actual: #{new_mode}"
    return false
  end
end

def transition_to_safe
  """Transición de Nominal a Safe"""
  puts "Iniciando transición Nominal → Safe..."
  
  current_mode = tlm("CHASQUI_II BEACON SAT_CURR_MODE")
  puts "Modo actual: #{current_mode}"
  
  cmd("CHASQUI_II SWITCHTOSAFE")
  wait(5)
  
  new_mode = tlm("CHASQUI_II BEACON SAT_CURR_MODE")
  
  if new_mode == "SAFE"
    puts "✓ Transición exitosa a modo SAFE"
    return true
  else
    puts "✗ Transición falló. Modo actual: #{new_mode}"
    return false
  end
end

# ============================================
# FUNCIONES DE PLAYBACK
# ============================================

def playback_beacon_data(start_ptr = 0, num_packets = 10)
  """Reproducir datos de beacon almacenados"""
  puts "Iniciando playback de beacons..."
  puts "  Inicio: #{start_ptr}"
  puts "  Paquetes: #{num_packets}"
  
  cmd("CHASQUI_II PLAYBACK with PARTITION BEACON, READPOINTER #{start_ptr}, NPACKETS #{num_packets}")
  
  # Monitorear recepción
  received = 0
  start_time = Time.now
  timeout = num_packets * 2
  
  while received < num_packets && (Time.now - start_time) < timeout
    begin
      wait_packet("CHASQUI_II", "BEACON", 1, 2)
      received += 1
      print "."
    rescue Timeout::Error
      next
    end
  end
  
  puts ""
  puts "✓ Playback completado: #{received}/#{num_packets} paquetes"
  return received
end

def playback_payload_data(start_ptr = 0, num_packets = 10)
  """Reproducir datos de payload almacenados"""
  puts "Iniciando playback de payload..."
  puts "  Inicio: #{start_ptr}"
  puts "  Paquetes: #{num_packets}"
  
  cmd("CHASQUI_II PLAYBACK with PARTITION PL, READPOINTER #{start_ptr}, NPACKETS #{num_packets}")
  
  # Similar al playback de beacon
  received = 0
  start_time = Time.now
  timeout = num_packets * 2
  
  while received < num_packets && (Time.now - start_time) < timeout
    begin
      wait_packet("CHASQUI_II", "PL", 1, 2)
      received += 1
      print "."
    rescue Timeout::Error
      next
    end
  end
  
  puts ""
  puts "✓ Playback de payload completado: #{received}/#{num_packets} paquetes"
  return received
end

def get_flash_pointers
  """Obtener punteros de lectura/escritura de flash"""
  puts "Obteniendo punteros de flash..."
  
  beacon_write = tlm("CHASQUI_II BEACON BEACON_FLASH_WRITE_PTR")
  beacon_read = tlm("CHASQUI_II BEACON BEACON_FLASH_READ_PTR")
  payload_write = tlm("CHASQUI_II BEACON PAYLOAD_FLASH_WRITE_PTR")
  payload_read = tlm("CHASQUI_II BEACON PAYLOAD_FLASH_READ_PTR")
  
  puts "Flash Pointers:"
  puts "  Beacon  - Write: #{beacon_write}, Read: #{beacon_read}"
  puts "  Payload - Write: #{payload_write}, Read: #{payload_read}"
  
  return {
    beacon_write: beacon_write,
    beacon_read: beacon_read,
    payload_write: payload_write,
    payload_read: payload_read
  }
end

# ============================================
# FUNCIONES DE CONFIGURACIÓN DE THRESHOLDS
# ============================================

def configure_mode_thresholds(exit_thresh = 8000, enter_thresh = 7500)
  """Configurar umbrales de cambio de modo"""
  puts "Configurando umbrales de modo..."
  puts "  Exit threshold: #{exit_thresh}mV"
  puts "  Enter threshold: #{enter_thresh}mV"
  
  cmd("CHASQUI_II SETMODETHRESHOLDS with EXITTHRESH #{exit_thresh}, ENTERTHRESH #{enter_thresh}")
  wait(2)
  
  puts "✓ Umbrales configurados"
end

def configure_battery_heater_thresholds(on_thresh = 1700, off_thresh = 1200)
  """Configurar umbrales del calentador de batería"""
  puts "Configurando umbrales del calentador..."
  puts "  On threshold: #{on_thresh}"
  puts "  Off threshold: #{off_thresh}"
  
  cmd("CHASQUI_II SETBATTHTTHRESHOLDS with HTRONTHRESH #{on_thresh}, HTROFFTHRESH #{off_thresh}")
  wait(2)
  
  puts "✓ Umbrales del calentador configurados"
end

# ============================================
# FUNCIONES DE DIAGNÓSTICO
# ============================================

def request_static_parameters
  """Solicitar paquete de parámetros estáticos"""
  puts "Solicitando parámetros estáticos..."
  
  cmd("CHASQUI_II ISSUEPACKET with PACKET STATICPAR, STREAM DEBUG")
  wait(2)
  
  # Esperar paquete
  begin
    wait_packet("CHASQUI_II", "STATICPARS", 1, 10)
    puts "✓ Parámetros estáticos recibidos"
    
    # Mostrar algunos valores importantes
    display_static_parameters()
    return true
  rescue Timeout::Error
    puts "✗ Timeout esperando parámetros estáticos"
    return false
  end
end

def display_static_parameters
  """Mostrar parámetros estáticos actuales"""
  eps_interval = tlm("CHASQUI_II STATICPARS EPSREADINTERVAL")
  uhf_interval = tlm("CHASQUI_II STATICPARS UHFREADINTERVAL")
  pl_interval = tlm("CHASQUI_II STATICPARS PLREADINTERVAL")
  
  puts "\nParámetros Estáticos:"
  puts "  EPS Read Interval: #{eps_interval}ms"
  puts "  UHF Read Interval: #{uhf_interval}ms"
  puts "  PL Read Interval: #{pl_interval}ms"
end

def request_dynamic_parameters
  """Solicitar paquete de parámetros dinámicos"""
  puts "Solicitando parámetros dinámicos..."
  
  cmd("CHASQUI_II ISSUEPACKET with PACKET DYNAMICPAR, STREAM DEBUG")
  wait(2)
  
  begin
    wait_packet("CHASQUI_II", "DYNAMICPARS", 1, 10)
    puts "✓ Parámetros dinámicos recibidos"
    
    display_dynamic_parameters()
    return true
  rescue Timeout::Error
    puts "✗ Timeout esperando parámetros dinámicos"
    return false
  end
end

def display_dynamic_parameters
  """Mostrar parámetros dinámicos actuales"""
  mode = tlm("CHASQUI_II DYNAMICPARS CURRMODE")
  valid_cmds = tlm("CHASQUI_II DYNAMICPARS VALIDCMDS")
  invalid_cmds = tlm("CHASQUI_II DYNAMICPARS INVALIDCMDS")
  
  puts "\nParámetros Dinámicos:"
  puts "  Modo Actual: #{mode}"
  puts "  Comandos Válidos: #{valid_cmds}"
  puts "  Comandos Inválidos: #{invalid_cmds}"
end

def full_system_diagnosis
  """Diagnóstico completo del sistema"""
  puts "="*60
  puts "DIAGNÓSTICO COMPLETO DEL SISTEMA"
  puts "="*60
  
  # Test de comunicación
  puts "\n1. Test de comunicación..."
  comm_ok = send_noop_command()
  
  # Parámetros estáticos
  puts "\n2. Obteniendo parámetros estáticos..."
  static_ok = request_static_parameters()
  
  # Parámetros dinámicos
  puts "\n3. Obteniendo parámetros dinámicos..."
  dynamic_ok = request_dynamic_parameters()
  
  # Estado de salud
  puts "\n4. Estado de salud..."
  display_health_status()
  
  # Punteros de flash
  puts "\n5. Punteros de memoria flash..."
  get_flash_pointers()
  
  puts "\n" + "="*60
  puts "RESUMEN DEL DIAGNÓSTICO"
  puts "="*60
  puts "Comunicación: #{comm_ok ? '✓' : '✗'}"
  puts "Parámetros estáticos: #{static_ok ? '✓' : '✗'}"
  puts "Parámetros dinámicos: #{dynamic_ok ? '✓' : '✗'}"
  puts "="*60
end

def display_health_status
  """Mostrar estado de salud actual"""
  begin
    voltage = tlm("CHASQUI_II BEACON MAIN_BATT_VOLT")
    current = tlm("CHASQUI_II BEACON MAIN_BATT_CURR")
    temp_cdh = tlm("CHASQUI_II BEACON TEMP_CDH")
    temp_eps = tlm("CHASQUI_II BEACON TEMP_EPS")
    mode = tlm("CHASQUI_II BEACON SAT_CURR_MODE")
    boot_count = tlm("CHASQUI_II BEACON BOOT_COUNTER")
    
    puts "Estado de Salud:"
    puts "  Batería: #{voltage}V, #{current}A"
    puts "  Temperatura CDH: #{temp_cdh}°C"
    puts "  Temperatura EPS: #{temp_eps}°C"
    puts "  Modo: #{mode}"
    puts "  Boot Counter: #{boot_count}"
  rescue
    puts "  No hay telemetría disponible"
  end
end

# ============================================
# EJEMPLO DE USO
# ============================================

# Para ejecutar estas funciones desde Script Runner:
#
# load 'procedures/automation/command_library.rb'
#
# # Test de comunicación
# send_noop_command()
#
# # Diagnóstico completo
# full_system_diagnosis()
#
# # Cambio de modo
# transition_to_nominal()
#
# # Playback de datos
# playback_beacon_data(0, 20)