# ============================================================================
# SCRIPT 13: VERIFICADOR DE PREDICCIONES GMAT
# ============================================================================
# Archivo: procedures/operations/verify_gmat_prediction.rb

def verify_gmat_prediction
  puts "="*70
  puts "VERIFICADOR DE PREDICCIONES GMAT"
  puts "="*70
  
  # Rutas
  gmat_dir = File.join(Cosmos::USERPATH, '..', 'tools', 'gmat')
  schedule_json = File.join(Cosmos::USERPATH, 'outputs', 'planning', 'pass_schedule.json')
  report_txt = File.join(Cosmos::USERPATH, 'outputs', 'planning', 'pass_schedule_report.txt')
  
  checks = []
  
  # 1. Verificar directorio GMAT
  puts "\n[CHECK 1/6] Verificando instalación GMAT..."
  if Dir.exist?(gmat_dir)
    puts "✓ Directorio GMAT encontrado"
    checks << true
  else
    puts "✗ Directorio GMAT no encontrado: #{gmat_dir}"
    checks << false
  end
  
  # 2. Verificar scripts GMAT
  puts "\n[CHECK 2/6] Verificando scripts..."
  
  required_files = [
    'chasqui_ii_contact_predictor.script',
    'process_gmat_contacts.py',
    'run_gmat_prediction.sh'
  ]
  
  required_files.each do |file|
    file_path = File.join(gmat_dir, file)
    if File.exist?(file_path)
      puts "  ✓ #{file}"
    else
      puts "  ✗ #{file} NO ENCONTRADO"
      checks << false
    end
  end
  
  # 3. Verificar calendario generado
  puts "\n[CHECK 3/6] Verificando calendario generado..."
  if File.exist?(schedule_json)
    file_age = ((Time.now - File.mtime(schedule_json)) / 3600).round(1)
    puts "✓ Calendario encontrado (#{file_age}h antiguo)"
    
    if file_age > 168  # 1 semana
      puts "  ⚠ Calendario antiguo (>1 semana), considerar regenerar"
    end
    
    checks << true
  else
    puts "✗ Calendario no encontrado: #{schedule_json}"
    puts "  Ejecutar: cd tools/gmat && ./run_gmat_prediction.sh"
    checks << false
  end
  
  # 4. Validar contenido del JSON
  puts "\n[CHECK 4/6] Validando contenido del calendario..."
  if File.exist?(schedule_json)
    begin
      schedule_data = JSON.parse(File.read(schedule_json), symbolize_names: true)
      
      puts "  Total de pases: #{schedule_data.length}"
      
      # Contar pases futuros
      now = Time.now
      future_passes = schedule_data.count do |p|
        Time.parse(p[:aos]) > now
      end
      
      puts "  Pases futuros: #{future_passes}"
      
      if future_passes > 0
        puts "✓ Calendario válido"
        checks << true
      else
        puts "⚠ No hay pases futuros, regenerar calendario"
        checks << false
      end
      
    rescue => e
      puts "✗ Error parseando JSON: #{e.message}"
      checks << false
    end
  end
  
  # 5. Verificar reporte de texto
  puts "\n[CHECK 5/6] Verificando reporte..."
  if File.exist?(report_txt)
    lines = File.readlines(report_txt).count
    puts "✓ Reporte encontrado (#{lines} líneas)"
    checks << true
  else
    puts "⚠ Reporte no encontrado (no crítico)"
  end
  
  # 6. Verificar TLE
  puts "\n[CHECK 6/6] Verificando TLE..."
  tle_file = File.join(gmat_dir, 'chasqui_ii.tle')
  
  if File.exist?(tle_file)
    tle_age = ((Time.now - File.mtime(tle_file)) / 86400).round(1)
    puts "✓ TLE encontrado (#{tle_age} días)"
    
    if tle_age > 7
      puts "  ⚠ TLE antiguo (>7 días), actualizar para mayor precisión"
    end
    
    checks << true
  else
    puts "⚠ TLE no encontrado (se usará configurado en script)"
  end
  
  # Resumen
  puts "\n" + "="*70
  successful = checks.count(true)
  total = checks.length
  
  if successful == total
    puts "✓✓✓ TODAS LAS VERIFICACIONES PASARON ✓✓✓"
    puts "Sistema listo para automatización"
  elsif successful >= total - 2
    puts "⚠⚠⚠ VERIFICACIÓN PARCIAL ⚠⚠⚠"
    puts "Sistema funcional pero con advertencias"
  else
    puts "✗✗✗ VERIFICACIÓN FALLIDA ✗✗✗"
    puts "Configurar GMAT antes de continuar"
  end
  
  puts "="*70
  
  return successful == total
end

# Ejecución desde Script Runner
if __FILE__ == $0
  verify_gmat_prediction()
end