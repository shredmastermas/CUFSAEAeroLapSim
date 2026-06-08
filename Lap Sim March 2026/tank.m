function hdot = tank(t, h)
hdot = -(.0002*sqrt(19.62*h))/(6*h-h^2);