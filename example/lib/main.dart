import 'package:definitely_not_tooltip/definitely_not_tooltip.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DefinitelyNotTooltip Demo',
      theme: ThemeData.dark(),
      home: const MyHomePage(title: 'DefinitelyNotTooltip Demo'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            DNTooltip(
              content: Container(
                color: Colors.red,
                width: 140,
                height: 15,
                child: const Center(
                  child: Text(
                    "I'm a custom content tooltip",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
              preferedLocation: TooltipLocation.bottom,
              verticalOffset: 35,
              margin: const EdgeInsets.all(1),
              padding: const EdgeInsets.all(1),
              decoration: BoxDecoration(
                color: const Color.fromARGB(255, 44, 44, 44),
                border: Border.all(
                  color: const Color.fromARGB(255, 59, 59, 59),
                ),
              ),
              child: Container(
                width: 120,
                height: 60,
                decoration: BoxDecoration(
                  color: const Color.fromARGB(255, 44, 44, 44),
                  border: Border.all(
                    color: const Color.fromARGB(255, 59, 59, 59),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
