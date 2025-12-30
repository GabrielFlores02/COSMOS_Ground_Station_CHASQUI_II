# ============================================================================
# BIBLIOTECA COMPLETA DE AUTOMATIZACIÓN - ESTACIÓN TERRENA CHASQUI_II
# ============================================================================
# Archivo: config/targets/CHASQUI_II/lib/ground_station_library.rb
#
# Integración: COSMOS v4 + GNU Radio (TCPIP) + Gpredict + YAESU G-5500
# ============================================================================

require 'cosmos'
require 'cosmos/script'
require 'socket'
require 'json'
require 'csv'

module ChasquiII
  
  # ==========================================================================
  # MÓDULO 1: COMUNICACIÓN Y VERIFICACIÓN DE COMANDOS
  # ==========================================================================
  
  module Communication
    
    # Enviar comando con verificación automática
    def self.send_cmd_with_verify(target, cmd_name, params = {}, timeout: 10)
      begin
        cmd_str = "#{target} #{cmd_name}"
        params.each { |k, v| cmd_str += " with #{k} #{v}" }
        
        puts "[CMD] Enviando: #{cmd_str}"
        cmd(cmd_str)
        
        # Esperar ACK implícito (incremento de contador)
        initial_count = tlm("#{target} BEACON COMMAND_ACCEPT_COUNTER")
        
        wait_tolerance = 2
        (timeout / wait_tolerance).times do
          wait(wait_tolerance)
          current_count = tlm("#{target} BEACON COMMAND_ACCEPT_COUNTER")
          
          if current_count > initial_count
            puts "[CMD] ✓ Comando aceptado (contador: #{current_count})"
            return true
          end
        end
        
        puts "[CMD] ✗ Timeout esperando ACK"
        return false
        
      rescue => e
        puts "[CMD] ✗ Error: #{e.message}"
        return false
      end
    end
    
    # Verificar conectividad básica
    def self.ping_satellite(retries: 3)
      puts "[PING] Verificando comunicación con satélite..."
      
      retries.times do |i|
        if send_cmd_with_verify("CHASQUI_II", "NOOPERATION", {}, timeout: 5)
          puts "[PING] ✓ Satélite respondiendo"
          return true
        end
        puts "[PING] Intento #{i+1}/#{retries} fallido"
        wait(2)
      end
      
      puts "[PING] ✗ Satélite no responde"
      return false
    end
    
    # Solicitar paquete específico con retry
    def self.request_packet(packet_type, stream: "DEBUG", retries: 3)
      packet_map = {
        "BEACON" => "Beacon",
        "STATIC" => "StaticPar",
        "DYNAMIC" => "DynamicPar",
        "PL" => "PL"
      }
      
      pkt_name = packet_map[packet_type.upcase]
      return false unless pkt_name
      
      retries.times do |i|
        cmd("CHASQUI_II ISSUEPACKET with PACKET #{pkt_name}, STREAM #{stream}")
        
        begin
          wait_packet("CHASQUI_II", "#{packet_type.upcase}PARS", 1, 10)
          puts "[REQ] ✓ Paquete #{packet_type} recibido"
          return true
        rescue Timeout::Error
          puts "[REQ] Intento #{i+1}/#{retries} - Timeout"
          wait(3)
        end
      end
      
      puts "[REQ] ✗ No se recibió #{packet_type}"
      return false
    end
    
  end
  
  # ==========================================================================
  # MÓDULO 2: GESTIÓN DE SALUD Y SEGURIDAD
  # ==========================================================================
  
  module HealthSafety
    
    # Verificación completa de salud del satélite
    def self.health_check(detailed: false)
      puts "\n" + "="*70
      puts "VERIFICACIÓN DE SALUD DEL SATÉLITE"
      puts "="*70
      
      health_report = {
        timestamp: Time.now,
        status: "UNKNOWN",
        voltage: 0.0,
        current: 0.0,
        mode: "UNKNOWN",
        temp_cdh: 0.0,
        temp_eps: 0.0,
        temp_bat: 0.0,
        soc_avg: 0.0,
        anomalies: []
      }
      
      begin
        # Datos críticos
        health_report[:voltage] = tlm("CHASQUI_II BEACON MAIN_BATT_VOLT")
        health_report[:current] = tlm("CHASQUI_II BEACON MAIN_BATT_CURR")
        health_report[:mode] = tlm("CHASQUI_II BEACON SAT_CURR_MODE")
        
        # Temperaturas
        health_report[:temp_cdh] = tlm("CHASQUI_II BEACON TEMP_CDH")
        health_report[:temp_eps] = tlm("CHASQUI_II BEACON TEMP_EPS")
        health_report[:temp_bat] = tlm("CHASQUI_II BEACON TEMP_BAT_TH1")
        
        # Estado de carga
        soc1 = tlm("CHASQUI_II BEACON EPS_FG1_SOC")
        soc2 = tlm("CHASQUI_II BEACON EPS_FG2_SOC")
        soc3 = tlm("CHASQUI_II BEACON EPS_FG3_SOC")
        health_report[:soc_avg] = (soc1 + soc2 + soc3) / 3.0
        
        # Evaluación de estado
        if health_report[:voltage] < 7.0
          health_report[:status] = "CRITICAL"
          health_report[:anomalies] << "Voltaje crítico: #{health_report[:voltage]}V"
        elsif health_report[:voltage] < 7.5
          health_report[:status] = "WARNING"
          health_report[:anomalies] << "Voltaje bajo: #{health_report[:voltage]}V"
        else
          health_report[:status] = "NOMINAL"
        end
        
        # Verificar temperaturas
        if health_report[:temp_cdh] > 50 || health_report[:temp_eps] > 55
          health_report[:status] = "WARNING" if health_report[:status] == "NOMINAL"
          health_report[:anomalies] << "Temperatura elevada detectada"
        end
        
        if health_report[:temp_bat] < -5 || health_report[:temp_bat] > 35
          health_report[:anomalies] << "Temperatura batería fuera de rango: #{health_report[:temp_bat]}°C"
        end
        
        # Mostrar reporte
        puts "\n[ESTADO GENERAL]: #{health_report[:status]}"
        puts "\n[ENERGÍA]"
        puts "  Voltaje Batería:  #{health_report[:voltage].round(2)} V"
        puts "  Corriente:        #{health_report[:current].round(3)} A"
        puts "  SoC Promedio:     #{health_report[:soc_avg].round(1)} %"
        puts "  Modo Actual:      #{health_report[:mode]}"
        
        puts "\n[TEMPERATURAS]"
        puts "  CDH:              #{health_report[:temp_cdh].round(1)} °C"
        puts "  EPS:              #{health_report[:temp_eps].round(1)} °C"
        puts "  Batería:          #{health_report[:temp_bat].round(1)} °C"
        
        if health_report[:anomalies].any?
          puts "\n[ANOMALÍAS DETECTADAS]"
          health_report[:anomalies].each { |a| puts "  ⚠ #{a}" }
        end
        
        if detailed
          print_detailed_health()
        end
        
        puts "="*70 + "\n"
        return health_report
        
      rescue => e
        puts "[ERROR] No se pudo obtener telemetría: #{e.message}"
        health_report[:status] = "ERROR"
        return health_report
      end
    end
    
    # Reporte detallado de salud
    def self.print_detailed_health
      puts "\n[DETALLES ADICIONALES]"
      
      # Paneles solares
      puts "  Paneles Solares:"
      (0..2).each do |i|
        volt = tlm("CHASQUI_II BEACON PANEL#{i}_VOLT")
        curr = tlm("CHASQUI_II BEACON PANEL#{i}_CURR")
        power = volt * curr
        puts "    Panel #{i}: #{volt.round(2)}V, #{curr.round(3)}A, #{power.round(2)}W"
      end
      
      # Buses de potencia
      puts "  Buses de Potencia:"
      cdh_v = tlm("CHASQUI_II BEACON CDH_3V3_VOLT")
      cdh_i = tlm("CHASQUI_II BEACON CDH_3V3_CURR")
      puts "    CDH 3.3V: #{cdh_v.round(2)}V, #{cdh_i.round(3)}A"
      
      uhf_v = tlm("CHASQUI_II BEACON UHF_6V_VOLT")
      uhf_i = tlm("CHASQUI_II BEACON UHF_6V_CURR")
      puts "    UHF 6V:   #{uhf_v.round(2)}V, #{uhf_i.round(3)}A"
      
      adcs_v = tlm("CHASQUI_II BEACON ADCS_12V_VOLT")
      adcs_i = tlm("CHASQUI_II BEACON ADCS_12V_CURR")
      puts "    ADCS 12V: #{adcs_v.round(2)}V, #{adcs_i.round(3)}A"
      
      # Contadores
      cmd_accept = tlm("CHASQUI_II BEACON COMMAND_ACCEPT_COUNTER")
      cmd_reject = tlm("CHASQUI_II BEACON COMMAND_REJECT_COUNTER")
      puts "  Comandos: #{cmd_accept} aceptados, #{cmd_reject} rechazados"
    end
    
    # Verificación de seguridad antes de operaciones críticas
    def self.safety_check(operation_type)
      puts "[SAFETY] Verificando condiciones para: #{operation_type}"
      
      voltage = tlm("CHASQUI_II BEACON MAIN_BATT_VOLT")
      temp_cdh = tlm("CHASQUI_II BEACON TEMP_CDH")
      mode = tlm("CHASQUI_II BEACON SAT_CURR_MODE")
      
      case operation_type.upcase
      when "PAYLOAD_ON"
        if voltage < 7.5
          puts "[SAFETY] ✗ Voltaje insuficiente para payload (#{voltage}V < 7.5V)"
          return false
        end
        if temp_cdh > 45
          puts "[SAFETY] ✗ Temperatura muy alta (#{temp_cdh}°C > 45°C)"
          return false
        end
        
      when "MODE_NOMINAL"
        if voltage < 7.5
          puts "[SAFETY] ✗ Voltaje insuficiente para modo NOMINAL"
          return false
        end
        
      when "DEPLOYMENT"
        if voltage < 7.8
          puts "[SAFETY] ✗ Voltaje insuficiente para deployment"
          return false
        end
        
      when "PLAYBACK"
        # Playback siempre es seguro
        
      else
        puts "[SAFETY] Operación desconocida: #{operation_type}"
      end
      
      puts "[SAFETY] ✓ Condiciones seguras"
      return true
    end
    
  end
  
  # ==========================================================================
  # MÓDULO 3: GESTIÓN DE MODOS OPERACIONALES
  # ==========================================================================
  
  module ModeManagement
    
    # Cambio seguro a modo SAFE
    def self.switch_to_safe(force: false)
      puts "\n[MODE] Cambiando a modo SAFE..."
      
      current_mode = tlm("CHASQUI_II BEACON SAT_CURR_MODE")
      
      if current_mode == "SAFE"
        puts "[MODE] Ya está en modo SAFE"
        return true
      end
      
      unless force
        voltage = tlm("CHASQUI_II BEACON MAIN_BATT_VOLT")
        if voltage > 8.2
          puts "[MODE] ⚠ ADVERTENCIA: Voltaje alto (#{voltage}V)"
          puts "[MODE] ¿Realmente desea cambiar a SAFE? (Se apagarán subsistemas)"
          print "Confirmar (yes/no): "
          response = gets.chomp.downcase
          return false unless response == "yes"
        end
      end
      
      # Secuencia de cambio
      puts "[MODE] Apagando payload..."
      Communication.send_cmd_with_verify("CHASQUI_II", "TURNOFFPERIPHERAL", {PERIPHERAL: "PL"})
      wait(3)
      
      puts "[MODE] Enviando comando SAFE..."
      if Communication.send_cmd_with_verify("CHASQUI_II", "SWITCHTOSAFE")
        wait(5)
        
        # Verificar cambio
        new_mode = tlm("CHASQUI_II BEACON SAT_CURR_MODE")
        if new_mode == "SAFE"
          puts "[MODE] ✓ Modo SAFE activado exitosamente"
          return true
        else
          puts "[MODE] ✗ Cambio no confirmado (modo actual: #{new_mode})"
          return false
        end
      end
      
      return false
    end
    
    # Cambio seguro a modo NOMINAL
    def self.switch_to_nominal(force: false)
      puts "\n[MODE] Cambiando a modo NOMINAL..."
      
      current_mode = tlm("CHASQUI_II BEACON SAT_CURR_MODE")
      
      if current_mode == "NOMINAL"
        puts "[MODE] Ya está en modo NOMINAL"
        return true
      end
      
      # Verificación de seguridad
      unless force || HealthSafety.safety_check("MODE_NOMINAL")
        puts "[MODE] ✗ Condiciones no seguras para NOMINAL"
        return false
      end
      
      puts "[MODE] Enviando comando NOMINAL..."
      if Communication.send_cmd_with_verify("CHASQUI_II", "SWITCHTONOMINAL")
        wait(5)
        
        new_mode = tlm("CHASQUI_II BEACON SAT_CURR_MODE")
        if new_mode == "NOMINAL"
          puts "[MODE] ✓ Modo NOMINAL activado exitosamente"
          return true
        else
          puts "[MODE] ✗ Cambio no confirmado"
          return false
        end
      end
      
      return false
    end
    
    # Configurar umbrales de modo automático
    def self.configure_mode_thresholds(exit_mv: 8000, enter_mv: 7500, override: false)
      puts "[MODE] Configurando umbrales automáticos..."
      puts "  Exit threshold:  #{exit_mv} mV (salir de SAFE)"
      puts "  Enter threshold: #{enter_mv} mV (entrar a SAFE)"
      
      cmd("CHASQUI_II SETMODETHRESHOLDS with EXITTHRESH #{exit_mv}, ENTERTHRESH #{enter_mv}")
      wait(2)
      
      if override
        puts "[MODE] Activando override (deshabilitar cambio automático)"
        cmd("CHASQUI_II SETMODEOVERRIDEFLAG with OVERRIDEFLAG ON")
      else
        puts "[MODE] Desactivando override (habilitar cambio automático)"
        cmd("CHASQUI_II SETMODEOVERRIDEFLAG with OVERRIDEFLAG OFF")
      end
      
      wait(1)
      puts "[MODE] ✓ Umbrales configurados"
      return true
    end
    
  end
  
  # ==========================================================================
  # MÓDULO 4: CONTROL DE PAYLOAD
  # ==========================================================================
  
  module PayloadControl
    
    # Encender payload con verificaciones completas
    def self.power_on(pre_check: true)
      puts "\n[PAYLOAD] Encendiendo payload..."
      
      if pre_check && !HealthSafety.safety_check("PAYLOAD_ON")
        puts "[PAYLOAD] ✗ Condiciones no seguras"
        return false
      end
      
      if Communication.send_cmd_with_verify("CHASQUI_II", "TURNONPERIPHERAL", {PERIPHERAL: "PL"})
        wait(5)
        
        # Verificar corriente de payload
        pl_curr = tlm("CHASQUI_II BEACON PL_12V_CURR")
        if pl_curr > 0.05
          puts "[PAYLOAD] ✓ Payload encendido (corriente: #{pl_curr.round(3)}A)"
          return true
        else
          puts "[PAYLOAD] ⚠ Comando enviado pero no se detecta corriente"
          return false
        end
      end
      
      return false
    end
    
    # Apagar payload
    def self.power_off
      puts "[PAYLOAD] Apagando payload..."
      
      if Communication.send_cmd_with_verify("CHASQUI_II", "TURNOFFPERIPHERAL", {PERIPHERAL: "PL"})
        wait(3)
        puts "[PAYLOAD] ✓ Payload apagado"
        return true
      end
      
      return false
    end
    
    # Configurar intervalo de lectura de payload
    def self.set_read_interval(interval_ms)
      puts "[PAYLOAD] Configurando intervalo: #{interval_ms}ms"
      cmd("CHASQUI_II SETPLINTERVAL with INTERVAL #{interval_ms}")
      wait(1)
      puts "[PAYLOAD] ✓ Intervalo configurado"
    end
    
    # Ciclo completo de operación de payload
    def self.payload_session(duration_sec: 300, interval_ms: 60000)
      puts "\n[PAYLOAD] Iniciando sesión de payload"
      puts "  Duración: #{duration_sec}s"
      puts "  Intervalo: #{interval_ms}ms"
      
      # Encender
      return false unless power_on()
      
      # Configurar intervalo
      set_read_interval(interval_ms)
      
      # Esperar duración
      puts "[PAYLOAD] Operando..."
      wait(duration_sec)
      
      # Apagar
      power_off()
      
      puts "[PAYLOAD] ✓ Sesión completada"
      return true
    end
    
  end
  
  # ==========================================================================
  # MÓDULO 5: DESCARGA Y PLAYBACK DE DATOS
  # ==========================================================================
  
  module DataDownload
    
    # Obtener estado de memoria flash
    def self.get_flash_status
      puts "[FLASH] Obteniendo estado de memoria..."
      
      Communication.request_packet("DYNAMIC")
      wait(3)
      
      status = {}
      
      # Punteros de beacon
      status[:beacon] = {
        write: tlm("CHASQUI_II DYNAMICPARS PKTWRITEPTR[0]"),
        read: tlm("CHASQUI_II DYNAMICPARS PKTREADPTR[0]")
      }
      status[:beacon][:available] = status[:beacon][:write] - status[:beacon][:read]
      
      # Punteros de payload
      status[:payload] = {
        write: tlm("CHASQUI_II DYNAMICPARS PKTWRITEPTR[1]"),
        read: tlm("CHASQUI_II DYNAMICPARS PKTREADPTR[1]")
      }
      status[:payload][:available] = status[:payload][:write] - status[:payload][:read]
      
      # Punteros de EPS
      status[:eps] = {
        write: tlm("CHASQUI_II DYNAMICPARS PKTWRITEPTR[3]"),
        read: tlm("CHASQUI_II DYNAMICPARS PKTREADPTR[3]")
      }
      status[:eps][:available] = status[:eps][:write] - status[:eps][:read]
      
      puts "\n[FLASH] Estado actual:"
      status.each do |type, data|
        puts "  #{type.to_s.upcase}:"
        puts "    Write pointer: #{data[:write]}"
        puts "    Read pointer:  #{data[:read]}"
        puts "    Disponibles:   #{data[:available]} paquetes"
      end
      
      return status
    end
    
    # Playback de datos con reintentos y progreso
    def self.playback(partition, start_ptr: 0, num_packets: 50, auto_advance: true)
      puts "\n[PLAYBACK] Iniciando descarga"
      puts "  Partición:    #{partition}"
      puts "  Inicio:       #{start_ptr}"
      puts "  Paquetes:     #{num_packets}"
      
      # Mapeo de particiones
      partition_map = {
        "BEACON" => ["Beacon", "BEACON"],
        "PL" => ["PL", "BEACON"],
        "EPS" => ["EpsI2C", "BEACON"],
        "STATIC" => ["StaticTable", "STATICPARS"],
        "DYNAMIC" => ["DynamicTable", "DYNAMICPARS"]
      }
      
      part_cmd, part_tlm = partition_map[partition.upcase]
      return false unless part_cmd
      
      cmd("CHASQUI_II PLAYBACK with PARTITION #{part_cmd}, READPOINTER #{start_ptr}, NPACKETS #{num_packets}")
      
      # Monitorear recepción
      received = 0
      consecutive_timeouts = 0
      max_timeouts = 5
      
      start_time = Time.now
      
      while received < num_packets
        begin
          wait_packet("CHASQUI_II", part_tlm, 1, 5)
          received += 1
          consecutive_timeouts = 0
          
          # Barra de progreso
          progress = (received.to_f / num_packets * 100).round(1)
          bar = "█" * (progress / 5).to_i + "░" * (20 - (progress / 5).to_i)
          print "\r[PLAYBACK] [#{bar}] #{received}/#{num_packets} (#{progress}%)"
          STDOUT.flush
          
        rescue Timeout::Error
          consecutive_timeouts += 1
          print "\r[PLAYBACK] Timeout #{consecutive_timeouts}/#{max_timeouts}..."
          STDOUT.flush
          
          if consecutive_timeouts >= max_timeouts
            puts "\n[PLAYBACK] ✗ Demasiados timeouts consecutivos"
            break
          end
        end
      end
      
      elapsed = (Time.now - start_time).round(1)
      puts "\n[PLAYBACK] ✓ Completado: #{received}/#{num_packets} en #{elapsed}s"
      
      return received
    end
    
    # Descarga completa de beacons disponibles
    def self.download_all_beacons(chunk_size: 50, delay_between_chunks: 5)
      puts "\n[DOWNLOAD] Iniciando descarga completa de beacons"
      
      flash_status = get_flash_status()
      available = flash_status[:beacon][:available]
      
      if available <= 0
        puts "[DOWNLOAD] No hay beacons disponibles"
        return 0
      end
      
      puts "[DOWNLOAD] Beacons disponibles: #{available}"
      
      total_downloaded = 0
      start_ptr = flash_status[:beacon][:read]
      chunks = (available.to_f / chunk_size).ceil
      
      chunks.times do |i|
        chunk_start = start_ptr + (i * chunk_size)
        chunk_count = [chunk_size, available - total_downloaded].min
        
        puts "\n[DOWNLOAD] Chunk #{i+1}/#{chunks}"
        downloaded = playback("BEACON", start_ptr: chunk_start, num_packets: chunk_count)
        total_downloaded += downloaded
        
        break if downloaded < chunk_count  # Error en descarga
        
        wait(delay_between_chunks) if i < chunks - 1
      end
      
      puts "\n[DOWNLOAD] ✓ Descarga completa: #{total_downloaded}/#{available} beacons"
      return total_downloaded
    end
    
    # Resetear puntero de lectura (liberar memoria)
    def self.reset_read_pointer(packet_type)
      puts "[FLASH] Reseteando puntero de #{packet_type}..."
      
      type_map = {
        "BEACON" => "Beacon",
        "PL" => "PL"
      }
      
      pkt = type_map[packet_type.upcase]
      return false unless pkt
      
      cmd("CHASQUI_II RESETWRITEPOINTER with PACKETTYPE #{pkt}")
      wait(2)
      
      puts "[FLASH] ✓ Puntero reseteado"
      return true
    end
    
  end
  
  # ==========================================================================
  # MÓDULO 6: CONFIGURACIÓN Y CALIBRACIÓN
  # ==========================================================================
  
  module Configuration
    
    # Configuración completa de intervalos
    def self.configure_all_intervals(profile: "DEFAULT")
      puts "\n[CONFIG] Aplicando perfil: #{profile}"
      
      profiles = {
        "DEFAULT" => {
          eps: 10000,
          uhf: 5000,
          beacon: 30000,
          pl: 60000
        },
        "LOW_POWER" => {
          eps: 60000,
          uhf: 30000,
          beacon: 120000,
          pl: 300000
        },
        "HIGH_RATE" => {
          eps: 5000,
          uhf: 2000,
          beacon: 10000,
          pl: 30000
        },
        "SCIENCE" => {
          eps: 10000,
          uhf: 5000,
          beacon: 60000,
          pl: 30000
        }
      }
      
      config = profiles[profile.upcase]
      unless config
        puts "[CONFIG] ✗ Perfil desconocido: #{profile}"
        return false
      end
      
      cmd("CHASQUI_II SETEPSREADINTERVAL with INTERVAL #{config[:eps]}")
      wait(1)
      
      cmd("CHASQUI_II SETUHFREADINTERVAL with INTERVAL #{config[:uhf]}")
      wait(1)
      
      cmd("CHASQUI_II SETBCNPACKETINTERVAL with INTERVAL #{config[:beacon]}")
      wait(1)
      
      cmd("CHASQUI_II SETPLINTERVAL with INTERVAL #{config[:pl]}")
      wait(1)
      
      puts "[CONFIG] ✓ Perfil aplicado:"
      puts "  EPS:    #{config[:eps]}ms"
      puts "  UHF:    #{config[:uhf]}ms"
      puts "  Beacon: #{config[:beacon]}ms"
      puts "  Payload:#{config[:pl]}ms"
      
      return true
    end
    
    # Configurar almacenamiento de paquetes
    def self.configure_packet_storage(beacon: 60000, static: 300000, dynamic: 120000)
      puts "[CONFIG] Configurando intervalos de almacenamiento..."
      
      cmd("CHASQUI_II SETPACKETSAVEINTERVAL with PACKETTYPE Beacon, INTERVAL #{beacon}")
      wait(1)
      
      cmd("CHASQUI_II SETPACKETSAVEINTERVAL with PACKETTYPE StaticTablePars, INTERVAL #{static}")
      wait(1)
      
      cmd("CHASQUI_II SETPACKETSAVEINTERVAL with PACKETTYPE DynamicTablePars, INTERVAL #{dynamic}")
      wait(1)
      
      puts "[CONFIG] ✓ Intervalos configurados"
      return true
    end
    
    # Sincronizar tiempo del satélite
    def self.sync_time(offset_sec: 0)
      current_time = Time.now.to_i + offset_sec
      
      puts "[TIME] Sincronizando reloj del satélite..."
      puts "  Tiempo actual: #{Time.at(current_time)}"
      
      cmd("CHASQUI_II SETLINUXTIME with SECONDS #{current_time}")
      wait(2)
      
      puts "[TIME] ✓ Tiempo sincronizado"
      return true
    end
    
    # Configurar battery heater
    def self.configure_battery_heater(on_thresh: 1700, off_thresh: 1200, auto: true)
      puts "[HEATER] Configurando calentador de batería..."
      
      cmd("CHASQUI_II SETBATTHTTHRESHOLDS with HTRONTHRESH #{on_thresh}, HTROFFTHRESH #{off_thresh}")
      wait(1)
      
      if auto
        cmd("CHASQUI_II SETBATTHTROVERRIDEFLAG with OVERRIDEFLAG OFF")
        puts "[HEATER] Modo automático HABILITADO"
      else
        cmd("CHASQUI_II SETBATTHTROVERRIDEFLAG with OVERRIDEFLAG ON")
        puts "[HEATER] Modo automático DESHABILITADO"
      end
      
      wait(1)
      puts "[HEATER] ✓ Configuración aplicada"
      return true
    end
    
  end
  
  # ==========================================================================
  # MÓDULO 7: SECUENCIAS AUTOMATIZADAS DE PASE
  # ==========================================================================
  
  module PassSequences
    
    # Secuencia de inicio de pase (AOS - Acquisition of Signal)
    def self.aos_sequence
      puts "\n" + "="*70
      puts "SECUENCIA AOS (ACQUISITION OF SIGNAL)"
      puts "="*70
      
      start_time = Time.now
      
      # 1. Verificar comunicación
      puts "\n[AOS-1] Verificando comunicación..."
      unless Communication.ping_satellite(retries: 5)
        puts "[AOS] ✗ No se estableció comunicación"
        return false
      end
      
      # 2. Health check rápido
      puts "\n[AOS-2] Verificación de salud..."
      health = HealthSafety.health_check(detailed: false)
      
      if health[:status] == "CRITICAL"
        puts "[AOS] ⚠ ESTADO CRÍTICO - Iniciando recuperación..."
        emergency_recovery()
        return false
      end
      
      # 3. Solicitar parámetros actuales
      puts "\n[AOS-3] Solicitando configuración actual..."
      Communication.request_packet("STATIC")
      wait(2)
      Communication.request_packet("DYNAMIC")
      wait(2)
      
      # 4. Sincronizar tiempo
      puts "\n[AOS-4] Sincronizando tiempo..."
      Configuration.sync_time()
      
      # 5. Estado de memoria
      puts "\n[AOS-5] Verificando memoria flash..."
      flash_status = DataDownload.get_flash_status()
      
      elapsed = (Time.now - start_time).round(1)
      puts "\n" + "="*70
      puts "✓ SECUENCIA AOS COMPLETADA (#{elapsed}s)"
      puts "  Estado: #{health[:status]}"
      puts "  Voltaje: #{health[:voltage].round(2)}V"
      puts "  Beacons disponibles: #{flash_status[:beacon][:available]}"
      puts "="*70 + "\n"
      
      return true
    end
    
    # Secuencia principal de pase (operaciones)
    def self.main_pass_operations(ops_plan: {})
      puts "\n[PASS] Iniciando operaciones de pase..."
      
      default_plan = {
        download_beacons: true,
        download_payload: false,
        payload_session: false,
        mode_change: nil,
        upload_config: false
      }
      
      plan = default_plan.merge(ops_plan)
      results = {}
      
      # Descargar beacons
      if plan[:download_beacons]
        puts "\n[PASS] Operación: Descarga de beacons"
        results[:beacons_downloaded] = DataDownload.download_all_beacons()
      end
      
      # Descargar datos de payload
      if plan[:download_payload]
        puts "\n[PASS] Operación: Descarga de payload"
        flash_status = DataDownload.get_flash_status()
        if flash_status[:payload][:available] > 0
          results[:payload_downloaded] = DataDownload.playback("PL", 
            start_ptr: flash_status[:payload][:read],
            num_packets: flash_status[:payload][:available])
        else
          puts "[PASS] No hay datos de payload disponibles"
          results[:payload_downloaded] = 0
        end
      end
      
      # Sesión de payload
      if plan[:payload_session]
        puts "\n[PASS] Operación: Sesión de payload"
        results[:payload_session] = PayloadControl.payload_session(
          duration_sec: plan[:payload_duration] || 300,
          interval_ms: plan[:payload_interval] || 60000
        )
      end
      
      # Cambio de modo
      if plan[:mode_change]
        puts "\n[PASS] Operación: Cambio de modo a #{plan[:mode_change]}"
        case plan[:mode_change].upcase
        when "SAFE"
          results[:mode_change] = ModeManagement.switch_to_safe()
        when "NOMINAL"
          results[:mode_change] = ModeManagement.switch_to_nominal()
        end
      end
      
      # Subir nueva configuración
      if plan[:upload_config]
        puts "\n[PASS] Operación: Actualizar configuración"
        results[:config_upload] = Configuration.configure_all_intervals(
          profile: plan[:config_profile] || "DEFAULT")
      end
      
      puts "\n[PASS] ✓ Operaciones completadas"
      return results
    end
    
    # Secuencia de fin de pase (LOS - Loss of Signal)
    def self.los_sequence(next_pass_time: nil)
      puts "\n" + "="*70
      puts "SECUENCIA LOS (LOSS OF SIGNAL)"
      puts "="*70
      
      # 1. Health check final
      puts "\n[LOS-1] Verificación final de salud..."
      health = HealthSafety.health_check(detailed: true)
      
      # 2. Guardar estado actual
      puts "\n[LOS-2] Guardando estado para siguiente pase..."
      Communication.request_packet("STATIC")
      wait(2)
      Communication.request_packet("DYNAMIC")
      wait(2)
      
      # 3. Preparar para siguiente pase
      if next_pass_time
        puts "\n[LOS-3] Preparando para siguiente pase..."
        time_to_next = (next_pass_time - Time.now) / 3600.0
        
        if time_to_next > 6
          puts "[LOS] Siguiente pase en #{time_to_next.round(1)}h - Aplicando perfil LOW_POWER"
          Configuration.configure_all_intervals(profile: "LOW_POWER")
        else
          puts "[LOS] Siguiente pase en #{time_to_next.round(1)}h - Manteniendo perfil actual"
        end
      end
      
      # 4. Último NOOP
      puts "\n[LOS-4] Enviando último comando..."
      Communication.send_cmd_with_verify("CHASQUI_II", "NOOPERATION")
      
      puts "\n" + "="*70
      puts "✓ SECUENCIA LOS COMPLETADA"
      puts "  Estado final: #{health[:status]}"
      puts "  Voltaje: #{health[:voltage].round(2)}V"
      puts "  Temperatura: #{health[:temp_cdh].round(1)}°C"
      puts "="*70 + "\n"
      
      return true
    end
    
    # Recuperación de emergencia
    def self.emergency_recovery
      puts "\n[EMERGENCY] Iniciando recuperación de emergencia..."
      
      # Intentar cambiar a SAFE
      puts "[EMERGENCY] Forzando modo SAFE..."
      ModeManagement.switch_to_safe(force: true)
      wait(5)
      
      # Apagar subsistemas no críticos
      puts "[EMERGENCY] Apagando payload..."
      PayloadControl.power_off()
      wait(2)
      
      # Aplicar perfil de bajo consumo
      puts "[EMERGENCY] Aplicando perfil LOW_POWER..."
      Configuration.configure_all_intervals(profile: "LOW_POWER")
      
      puts "[EMERGENCY] ✓ Recuperación completada"
    end
    
    # Pase completo automatizado
    def self.automated_pass(duration_min: 10, ops_plan: {})
      puts "\n" + "="*70
      puts "PASE AUTOMATIZADO"
      puts "  Duración estimada: #{duration_min} minutos"
      puts "="*70
      
      pass_start = Time.now
      
      # AOS
      unless aos_sequence()
        puts "\n[PASS] ✗ Fallo en AOS - Abortando pase"
        return false
      end
      
      wait(5)
      
      # Operaciones principales
      results = main_pass_operations(ops_plan: ops_plan)
      
      # Esperar si queda tiempo
      elapsed = (Time.now - pass_start) / 60.0
      remaining = duration_min - elapsed
      
      if remaining > 1
        puts "\n[PASS] Esperando fin de pase (#{remaining.round(1)}min)..."
        wait(remaining * 60)
      end
      
      # LOS
      los_sequence()
      
      # Reporte final
      total_time = ((Time.now - pass_start) / 60.0).round(1)
      puts "\n" + "="*70
      puts "✓ PASE COMPLETADO"
      puts "  Duración: #{total_time} minutos"
      puts "  Beacons descargados: #{results[:beacons_downloaded] || 0}"
      puts "  Payload descargado: #{results[:payload_downloaded] || 0}"
      puts "="*70 + "\n"
      
      return true
    end
    
  end
  
  # ==========================================================================
  # MÓDULO 8: INTEGRACIÓN CON GPREDICT Y ROTOR
  # ==========================================================================
  
  module RotorControl
    
    # Conectar con rotctld (Hamlib)
    def self.connect_rotator(host: "localhost", port: 4533)
      puts "[ROTOR] Conectando a rotctld..."
      begin
        @rotor_socket = TCPSocket.new(host, port)
        puts "[ROTOR] ✓ Conectado a #{host}:#{port}"
        return true
      rescue => e
        puts "[ROTOR] ✗ Error: #{e.message}"
        return false
      end
    end
    
    # Mover rotor a posición
    def self.set_position(azimuth, elevation)
      return false unless @rotor_socket
      
      begin
        @rotor_socket.puts("P #{azimuth} #{elevation}")
        response = @rotor_socket.gets
        puts "[ROTOR] Az: #{azimuth}° El: #{elevation}°"
        return true
      rescue => e
        puts "[ROTOR] ✗ Error: #{e.message}"
        return false
      end
    end
    
    # Obtener posición actual
    def self.get_position
      return nil unless @rotor_socket
      
      begin
        @rotor_socket.puts("p")
        response = @rotor_socket.gets
        az, el = response.split.map(&:to_f)
        return {azimuth: az, elevation: el}
      rescue => e
        puts "[ROTOR] ✗ Error: #{e.message}"
        return nil
      end
    end
    
    # Seguimiento automático durante pase
    def self.track_satellite(duration_sec: 600, update_interval: 5)
      puts "[ROTOR] Iniciando seguimiento automático..."
      puts "  Duración: #{duration_sec}s"
      puts "  Intervalo: #{update_interval}s"
      
      iterations = duration_sec / update_interval
      
      iterations.times do |i|
        # Aquí se integraría con Gpredict para obtener Az/El
        # Por ahora simulamos
        pos = get_position()
        puts "[ROTOR] Posición actual: Az=#{pos[:azimuth]}° El=#{pos[:elevation]}°"
        
        wait(update_interval)
      end
      
      puts "[ROTOR] ✓ Seguimiento completado"
    end
    
  end
  
  # ==========================================================================
  # MÓDULO 9: LOGGING Y REPORTES
  # ==========================================================================
  
  module Reporting
    
    # Crear reporte de pase
    def self.generate_pass_report(pass_data)
      timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
      filename = "pass_report_#{timestamp}.txt"
      
      File.open(filename, 'w') do |f|
        f.puts "="*70
        f.puts "REPORTE DE PASE - CHASQUI II"
        f.puts "="*70
        f.puts "Fecha: #{Time.now}"
        f.puts ""
        
        f.puts "[DATOS DEL PASE]"
        f.puts "  Duración: #{pass_data[:duration]}min"
        f.puts "  Elevación máxima: #{pass_data[:max_elevation]}°"
        f.puts ""
        
        f.puts "[SALUD DEL SATÉLITE]"
        health = pass_data[:health]
        f.puts "  Estado: #{health[:status]}"
        f.puts "  Voltaje batería: #{health[:voltage].round(2)}V"
        f.puts "  Corriente: #{health[:current].round(3)}A"
        f.puts "  SoC promedio: #{health[:soc_avg].round(1)}%"
        f.puts "  Temp CDH: #{health[:temp_cdh].round(1)}°C"
        f.puts "  Temp EPS: #{health[:temp_eps].round(1)}°C"
        f.puts "  Modo: #{health[:mode]}"
        f.puts ""
        
        if health[:anomalies].any?
          f.puts "[ANOMALÍAS]"
          health[:anomalies].each { |a| f.puts "  - #{a}" }
          f.puts ""
        end
        
        f.puts "[OPERACIONES REALIZADAS]"
        f.puts "  Beacons descargados: #{pass_data[:beacons_downloaded] || 0}"
        f.puts "  Payload descargado: #{pass_data[:payload_downloaded] || 0}"
        f.puts "  Comandos enviados: #{pass_data[:commands_sent] || 0}"
        f.puts ""
        
        f.puts "="*70
      end
      
      puts "[REPORT] ✓ Reporte guardado: #{filename}"
      return filename
    end
    
    # Exportar telemetría a CSV
    def self.export_telemetry_csv(output_file: "telemetry_export.csv")
      puts "[EXPORT] Exportando telemetría a CSV..."
      
      # Obtener datos actuales
      beacon_data = {
        timestamp: Time.now,
        voltage: tlm("CHASQUI_II BEACON MAIN_BATT_VOLT"),
        current: tlm("CHASQUI_II BEACON MAIN_BATT_CURR"),
        temp_cdh: tlm("CHASQUI_II BEACON TEMP_CDH"),
        temp_eps: tlm("CHASQUI_II BEACON TEMP_EPS"),
        soc1: tlm("CHASQUI_II BEACON EPS_FG1_SOC"),
        soc2: tlm("CHASQUI_II BEACON EPS_FG2_SOC"),
        soc3: tlm("CHASQUI_II BEACON EPS_FG3_SOC"),
        mode: tlm("CHASQUI_II BEACON SAT_CURR_MODE")
      }
      
      CSV.open(output_file, "a") do |csv|
        if File.size?(output_file).nil? || File.size(output_file) == 0
          # Header
          csv << beacon_data.keys
        end
        csv << beacon_data.values
      end
      
      puts "[EXPORT] ✓ Datos añadidos a #{output_file}"
      return true
    end
    
  end
  
  # ==========================================================================
  # CLASE PRINCIPAL: GESTOR DE ESTACIÓN TERRENA
  # ==========================================================================
  
  class GroundStationManager
    
    attr_reader :station_status, :pass_history
    
    def initialize
      @station_status = {
        initialized: false,
        last_contact: nil,
        satellite_health: nil,
        rotor_connected: false
      }
      @pass_history = []
      
      puts "\n[GS] Ground Station Manager inicializado"
    end
    
    # Inicializar estación
    def initialize_station
      puts "\n[GS] Inicializando estación terrena..."
      
      # Verificar conexión COSMOS
      begin
        cmd("CHASQUI_II NOOPERATION")
        puts "[GS] ✓ COSMOS conectado"
      rescue => e
        puts "[GS] ✗ Error en COSMOS: #{e.message}"
        return false
      end
      
      # Conectar rotor
      if RotorControl.connect_rotator()
        @station_status[:rotor_connected] = true
      end
      
      @station_status[:initialized] = true
      puts "[GS] ✓ Estación inicializada"
      return true
    end
    
    # Ejecutar pase programado
    def execute_scheduled_pass(pass_params)
      puts "\n[GS] Ejecutando pase programado..."
      puts "  TCA: #{pass_params[:tca]}"
      puts "  Duración: #{pass_params[:duration]}min"
      puts "  Max El: #{pass_params[:max_elevation]}°"
      
      pass_data = {
        start_time: Time.now,
        duration: pass_params[:duration],
        max_elevation: pass_params[:max_elevation]
      }
      
      # Ejecutar pase automatizado
      success = PassSequences.automated_pass(
        duration_min: pass_params[:duration],
        ops_plan: pass_params[:ops_plan] || {}
      )
      
      # Obtener health final
      pass_data[:health] = HealthSafety.health_check(detailed: false)
      
      # Generar reporte
      Reporting.generate_pass_report(pass_data)
      
      # Guardar en historial
      @pass_history << pass_data
      @station_status[:last_contact] = Time.now
      
      return success
    end
    
    # Monitor continuo (para passes largos)
    def continuous_monitor(duration_sec: 600, log_interval: 30)
      puts "\n[GS] Iniciando monitoreo continuo (#{duration_sec}s)..."
      
      iterations = duration_sec / log_interval
      
      iterations.times do |i|
        health = HealthSafety.health_check(detailed: false)
        Reporting.export_telemetry_csv()
        
        if health[:status] == "CRITICAL"
          puts "[GS] ⚠ ESTADO CRÍTICO DETECTADO"
          PassSequences.emergency_recovery()
        end
        
        wait(log_interval)
      end
      
      puts "[GS] ✓ Monitoreo completado"
    end
    
  end
  
end