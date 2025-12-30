# ============================================================================
# SCRIPT 4: PASE COMPLETO AUTOMATIZADO
# ============================================================================
# Archivo: procedures/operations/automated_full_pass.rb

load_utility 'ground_station_library'

def automated_full_pass(pass_params = {})
  puts "\n" + "="*70
  puts "PASE COMPLETAMENTE AUTOMATIZADO"
  puts "="*70
  
  # Parámetros por defecto
  params = {
    start_time: Time.now + 60,  # Comenzar en 1 minuto
    duration: 10,               # 10 minutos
    max_elevation: 45,          # 45 grados
    auto_commands: true,
    auto_download: true
  }.merge(pass_params)
  
  puts "\nCONFIGURACIÓN DEL PASE:"
  puts "  Inicio:           #{params[:start_time].strftime('%Y-%m-%d %H:%M:%S')}"
  puts "  Duración:         #{params[:duration]} minutos"
  puts "  Elevación máx:    #{params[:max_elevation]}°"
  puts "  Auto comandos:    #{params[:auto_commands] ? 'SÍ' : 'NO'}"
  puts "  Auto descarga:    #{params[:auto_download] ? 'SÍ' : 'NO'}"
  puts "="*70
  
  # Confirmación
  puts "\nPresione ENTER para continuar o Ctrl+C para cancelar..."
  gets
  
  success = true
  
  begin
    # FASE 1: PRE-PASE
    puts "\n" + "="*70
    puts "FASE 1: VERIFICACIÓN PRE-PASE"
    puts "="*70
    
    unless pre_pass_checks(params[:start_time], params[:duration], params[:max_elevation])
      puts "\n✗ FALLO en verificación pre-pase"
      puts "¿Desea continuar de todas formas? (y/n):"
      response = gets.chomp.downcase
      return false unless response == 'y'
    end
    
    # Esperar hasta tiempo de inicio
    wait_time = params[:start_time] - Time.now
    
    if wait_time > 0
      puts "\n⏰ Esperando inicio del pase..."
      puts "Tiempo restante: #{(wait_time/60.0).round(1)} minutos"
      
      # Countdown
      while wait_time > 0
        mins = (wait_time / 60).to_i
        secs = (wait_time % 60).to_i
        print "\r[COUNTDOWN] #{mins}:#{secs.to_s.rjust(2,'0')} hasta inicio..."
        STDOUT.flush
        
        wait(1)
        wait_time = params[:start_time] - Time.now
      end
      puts "\n"
    end
    
    # FASE 2: DURANTE EL PASE
    puts "\n" + "="*70
    puts "FASE 2: MONITOREO EN TIEMPO REAL"
    puts "="*70
    
    pass_result = monitor_pass_real_time(
      auto_commands: params[:auto_commands],
      auto_download: params[:auto_download]
    )
    
    puts "\n✓ Fase de monitoreo completada"
    puts "  Paquetes recibidos: #{pass_result[:packets]}"
    puts "  Alertas generadas:  #{pass_result[:alerts]}"
    
    # FASE 3: POST-PASE
    puts "\n" + "="*70
    puts "FASE 3: ANÁLISIS POST-PASE"
    puts "="*70
    
    wait(5)  # Esperar que se escriban todos los logs
    
    unless post_pass_analysis()
      puts "⚠ Advertencia: Problemas en análisis post-pase"
      success = false
    end
    
  rescue Interrupt
    puts "\n\n⚠ PASE INTERRUMPIDO POR USUARIO"
    success = false
    
    # Intentar guardar lo que se pueda
    begin
      post_pass_analysis()
    rescue
      puts "⚠ No se pudo generar análisis post-pase"
    end
    
  rescue => e
    puts "\n✗ ERROR DURANTE EL PASE: #{e.message}"
    puts e.backtrace.first(5)
    success = false
  end
  
  # Resumen final
  puts "\n" + "="*70
  if success
    puts "✓✓✓ PASE AUTOMATIZADO COMPLETADO EXITOSAMENTE ✓✓✓"
  else
    puts "⚠⚠⚠ PASE COMPLETADO CON ERRORES ⚠⚠⚠"
  end
  puts "="*70
  
  return success
end

# Ejecución desde Script Runner
if __FILE__ == $0
  # Solicitar parámetros
  puts "CONFIGURACIÓN DE PASE AUTOMATIZADO"
  puts "="*50
  
  start_str = ask("Hora de inicio (YYYY-MM-DD HH:MM:SS):")
  duration = ask("Duración (minutos):").to_i
  max_el = ask("Elevación máxima (grados):").to_i
  auto_cmd = ask("¿Comandos automáticos? (y/n):").downcase == 'y'
  auto_dl = ask("¿Descarga automática? (y/n):").downcase == 'y'
  
  params = {
    start_time: Time.parse(start_str),
    duration: duration,
    max_elevation: max_el,
    auto_commands: auto_cmd,
    auto_download: auto_dl
  }
  
  automated_full_pass(params)
end